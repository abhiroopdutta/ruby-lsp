# typed: strict
# frozen_string_literal: true

require "ruby_lsp/requests/support/educational_diagnostic"

module RubyLsp
  module Requests
    # ![Diagnostics demo](../../misc/diagnostics.gif)
    #
    # The
    # [diagnostics](https://microsoft.github.io/language-server-protocol/specification#textDocument_publishDiagnostics)
    # request informs the editor of RuboCop offenses for a given file.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> diagnostics: incorrect indentation
    # end
    # ```
    class Diagnostics < BaseRequest
      extend T::Sig

      sig { params(uri: String, document: Document).void }
      def initialize(uri, document)
        super(document)

        @uri = uri
        @tips = T.let([], T::Array[LanguageServer::Protocol::Interface::Diagnostic])
      end

      sig do
        override.returns(
          T.nilable(
            T.any(
              T.all(T::Array[Support::RuboCopDiagnostic], Object),
              T.all(T::Array[Support::SyntaxErrorDiagnostic], Object),
              T.all(T::Array[LanguageServer::Protocol::Interface::Diagnostic], Object),
            ),
          ),
        )
      end
      def run
        return if @document.syntax_error?

        visit(@document.tree) if @document.parsed?

        @tips
      end

      sig { override.params(node: SyntaxTree::ClassDeclaration).void }
      def visit_class(node)
        return if node.nil?
        return if node.superclass.nil?

        constant = node.constant.constant
        constant_location = node.constant.location
        superclass = node.superclass.value
        superclass_location = node.superclass.value.location

        message = <<~MSG
          #{constant.value} is a class that inherits from #{superclass.value}.
          This gives #{constant.value} access to all of the methods of #{superclass.value}.
        MSG

        range = LanguageServer::Protocol::Interface::Range.new(
          start: LanguageServer::Protocol::Interface::Position.new(
            line: constant_location.start_line - 1,
            character: constant_location.start_column,
          ),
          end: LanguageServer::Protocol::Interface::Position.new(
            line: superclass_location.end_line - 1,
            character: superclass_location.end_column,
          ),
        )

        @tips << Support::EducationalDiagnostic.new(message, range)

        super
      end
    end
  end
end
