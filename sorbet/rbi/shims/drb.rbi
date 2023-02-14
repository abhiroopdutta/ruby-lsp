# typed: true

class DRb::DRbObject
  sig { returns(T.nilable(RubyLsp::Job)) }
  def pop_request; end

  sig { params(result: [T::Hash[Symbol, T.untyped], RubyLsp::Result]).void }
  def push_response(result); end

  sig { returns(RubyLsp::Store) }
  def store; end

  sig { params(id: T.any(Integer, String)).void }
  def remove_job_handle(id); end
 end
