# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Extensions
    class Visitor < SyntaxTree::Visitor
      extend T::Sig
      extend T::Helpers
      include Requests::Support::Common

      abstract!

      sig { params(kwargs: T.untyped).void }
      def initialize(**kwargs)
        super()
      end

      sig { abstract.returns(Object) }
      def run; end
    end
  end
end
