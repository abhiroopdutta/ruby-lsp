# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # :nodoc:
    class BaseRequest < SyntaxTree::Visitor
      class RequestHookError < StandardError; end
      extend T::Sig
      extend T::Helpers
      include Support::Common

      abstract!

      class << self
        extend T::Sig

        sig { void }
        def accept_after_request!
          @accept_after_request = T.let(true, T.nilable(T::Boolean))
        end

        sig { returns(T::Array[T.class_of(Extensions::Visitor)]) }
        def after_request_hooks
          @after_request_hooks ||= T.let([], T.nilable(T::Array[T.class_of(Extensions::Visitor)]))
        end

        sig { params(hook: T.class_of(Extensions::Visitor)).void }
        def after_request(hook)
          raise RequestHookError, "Request #{name} does not accept after_request hooks" unless @accept_after_request

          after_request_hooks << hook
        end
      end

      # We must accept rest keyword arguments here, so that the argument count matches when
      # SyntaxTree::WithScope#initialize invokes `super` for Sorbet. We don't actually use these parameters for
      # anything. We can remove these arguments once we drop support for Ruby 2.7
      # https://github.com/ruby-syntax-tree/syntax_tree/blob/4dac90b53df388f726dce50ce638a1ba71cc59f8/lib/syntax_tree/with_scope.rb#L122
      sig { params(document: Document, _kwargs: T.untyped).void }
      def initialize(document, **_kwargs)
        @document = document

        # Parsing the document here means we're taking a lazy approach by only doing it when the first feature request
        # is received by the server. This happens because {Document#parse} remembers if there are new edits to be parsed
        @document.parse

        super()
      end

      sig { returns(Object) }
      def run_request
        response = T.let(run, Object)
        self.class.after_request_hooks.each { |hook| response = hook.new(response: response, **hook_parameters).run }
        response
      end

      sig { abstract.returns(Object) }
      def run; end

      sig { overridable.returns(T::Hash[Symbol, T.untyped]) }
      def hook_parameters
        {}
      end
    end
  end
end
