# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Extensions
    module Middleware
      # Inherit from this class if your extension wants to provide a middleware for the hover feature. As long as the
      # extension's middleware class is required by the extension, it will be automatically registered
      class Hover
        extend T::Sig
        extend T::Helpers
        include Requests::Support::RequestHelpers

        abstract!

        class << self
          extend T::Sig

          sig { params(child_class: T.class_of(Hover)).void }
          def inherited(child_class)
            Requests::Hover.middleware << child_class
            super
          end
        end

        sig do
          params(
            document: Document,
            position: Document::PositionShape,
            response: T.nilable(Interface::Hover),
          ).void
        end
        def initialize(document, position, response)
          @document = document
          @position = position
          @response = response
        end

        # The only method that needs to be implemented is `run`. The instance of the middleware class will have access
        # to all parameters as instance variables in addition to the previous response coming from other middleware. The
        # result of executing this method should argument previous responses and never override them
        sig { abstract.returns(T.nilable(Interface::Hover)) }
        def run; end
      end
    end
  end
end
