# typed: strict
# frozen_string_literal: true

require "drb/drb"

module RubyLsp
  Interface = LanguageServer::Protocol::Interface
  Constant = LanguageServer::Protocol::Constant
  Transport = LanguageServer::Protocol::Transport

  class Server
    extend T::Sig

    sig { void }
    def initialize
      @writer = T.let(Transport::Stdio::Writer.new, Transport::Stdio::Writer)
      @reader = T.let(Transport::Stdio::Reader.new, Transport::Stdio::Reader)

      @global_state = T.let(GlobalState.new, GlobalState)
      @responder = T.let(new_responder, Thread)
      @drb_uri = T.let(DRb.start_service("drbunix:", @global_state).uri, String)
      @workers = T.let([], T::Array[Integer])
    end

    sig { void }
    def start
      warn("Starting Ruby LSP...")

      # Requests that have to be executed sequentially or in the main process are implemented here. All other requests
      # fall under the else branch which just pushes requests to the queue
      @reader.read do |request|
        case request[:method]
        when "initialize", "textDocument/didOpen", "textDocument/didClose", "textDocument/didChange"
          result = Executor.new(@global_state.store).execute(request)
          finalize_request(result, request)
        when "initialized"
          spawn_workers
        when "$/cancelRequest"
          # Cancel the job if it's still in the queue
          @global_state.cancel_job(request[:params][:id])
        when "shutdown"
          warn("Shutting down Ruby LSP...")

          # Close the queue so that we can no longer receive items
          # @job_queue.close
          # # Clear any remaining jobs so that the thread can terminate
          # @job_queue.clear
          # @jobs.clear
          # Wait until the thread is finished
          @global_state.shutdown
          @responder.join
          @global_state.store.clear

          @workers.each { |pid| Process.waitpid(pid) }
          DRb.stop_service

          finalize_request(Result.new(response: nil, notifications: []), request)
        when "exit"
          # We return zero if shutdown has already been received or one otherwise as per the recommendation in the spec
          # https://microsoft.github.io/language-server-protocol/specification/#exit
          status = @global_state.store.empty? ? 0 : 1
          exit(status)
        else
          @global_state.push_request(request)
        end
      end
    end

    private

    sig { returns(Thread) }
    def new_responder
      Thread.new do
        # Thread::Queue#pop is thread safe and will wait until an item is available
        loop do
          request, result = T.let(@global_state.pop_response, T.nilable([T::Hash[Symbol, T.untyped], Result]))
          # The only time when the job is nil is when the queue is closed and we can then terminate the thread
          next sleep(0.0001) if request.nil? || result.nil?

          finalize_request(result, request)
        rescue GlobalState::QueueClosedError
          break
        end
      end
    end

    # Finalize a Queue::Result. All IO operations should happen here to avoid any issues with cancelling requests
    sig { params(result: Result, request: T::Hash[Symbol, T.untyped]).void }
    def finalize_request(result, request)
      @global_state.mutex.synchronize do
        error = result.error
        response = result.response

        # If the response include any notifications, go through them and publish each one
        result.notifications.each { |n| @writer.write(method: n.message, params: n.params) }

        if error
          @writer.write(
            id: request[:id],
            error: {
              code: Constant::ErrorCodes::INTERNAL_ERROR,
              message: error.inspect,
              data: request.to_json,
            },
          )
        elsif response != VOID
          @writer.write(id: request[:id], result: response)
        end

        request_time = result.request_time
        if request_time
          @writer.write(method: "telemetry/event", params: telemetry_params(request, request_time, error))
        end
      end
    end

    sig do
      params(
        request: T::Hash[Symbol, T.untyped],
        request_time: Float,
        error: T.nilable(Exception),
      ).returns(T::Hash[Symbol, T.any(String, Float)])
    end
    def telemetry_params(request, request_time, error)
      uri = request.dig(:params, :textDocument, :uri)
      params = {
        request: request[:method],
        lspVersion: RubyLsp::VERSION,
        requestTime: request_time,
      }

      if error
        params[:errorClass] = error.class.name
        params[:errorMessage] = error.message

        log_params = request[:params]
        params[:params] = log_params.reject { |k, _| k == :textDocument }.to_json if log_params

        backtrace = error.backtrace
        params[:backtrace] = backtrace.map { |bt| bt.sub(/^#{Dir.home}/, "~") }.join("\n") if backtrace
      end

      params[:uri] = uri.sub(%r{.*://#{Dir.home}}, "~") if uri
      params
    end

    sig { void }
    def spawn_workers
      @global_state.store.worker_count.times do
        @workers << fork do
          DRb.start_service
          global_state = DRb::DRbObject.new_with_uri(@drb_uri)

          loop do
            job = T.let(global_state.pop_request, T.nilable(Job))

            # The only time when the job is nil is when the queue is closed and we can then terminate the thread
            next sleep(0.0001) if job.nil?

            request = job.request
            global_state.remove_job_handle(request[:id])

            result = if job.cancelled
              # We need to return nil to the client even if the request was cancelled
              Result.new(response: nil, notifications: [])
            else
              Executor.new(global_state.store).execute(request)
            end

            global_state.push_response([request, result])
          rescue GlobalState::QueueClosedError
            break
          end
        end
      end
    end
  end
end
