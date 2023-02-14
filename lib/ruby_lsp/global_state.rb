# typed: strict
# frozen_string_literal: true

module RubyLsp
  class GlobalState
    extend T::Sig

    class QueueClosedError < StandardError; end

    sig { returns(Store) }
    attr_reader :store

    sig { returns(Mutex) }
    attr_reader :mutex

    sig { void }
    def initialize
      @store = T.let(Store.new, Store)
      @request_queue = T.let([], T::Array[Job])
      @response_queue = T.let([], T::Array[[T::Hash[Symbol, T.untyped], Result]])

      @mutex = T.let(Mutex.new, Mutex)
      @jobs = T.let({}, T::Hash[T.any(String, Integer), Job])
      @queue_closed = T.let(false, T::Boolean)
    end

    sig { params(id: T.any(Integer, String)).void }
    def cancel_job(id)
      @mutex.synchronize { @jobs[id]&.cancel }
    end

    sig { params(request: T::Hash[Symbol, T.untyped]).void }
    def push_request(request)
      # Default case: push the request to the queue to be executed by the worker
      job = Job.new(request: request, cancelled: false)

      # Remember a handle to the job, so that we can cancel it
      @mutex.synchronize { @jobs[request[:id]] = job }
      @request_queue << job
    end

    sig { returns(T.nilable(Job)) }
    def pop_request
      raise QueueClosedError if @queue_closed

      @mutex.synchronize do
        @request_queue.pop
      end
    end

    sig { params(result: [T::Hash[Symbol, T.untyped], Result]).void }
    def push_response(result)
      @response_queue << result
    end

    sig { returns(T.nilable([T::Hash[Symbol, T.untyped], Result])) }
    def pop_response
      raise QueueClosedError if @queue_closed

      @mutex.synchronize do
        @response_queue.pop
      end
    end

    sig { params(id: T.any(Integer, String)).void }
    def remove_job_handle(id)
      @mutex.synchronize { @jobs.delete(id) }
    end

    sig { void }
    def shutdown
      @queue_closed = true
      @request_queue.clear
      @response_queue.clear
    end
  end
end
