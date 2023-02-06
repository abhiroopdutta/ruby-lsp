# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class Tip < BaseRequest
      extend T::Sig

      sig { params(document: Document, uri: String).void }
      def initialize(document, uri)
        super(document)

        @tips = T.let([], T::Array[Interface::Diagnostic])
        @uri = uri
      end

      sig { override.returns(T.nilable(T::Array[Interface::Diagnostic])) }
      def run
        return if @document.syntax_error?

        visit(@document.tree)
        @tips
      end

      sig { params(node: SyntaxTree::ClassDeclaration).void }
      def visit_class(node)
        if node.superclass
          range = range_between_nodes(node.constant, node.superclass)
          class_name = node.constant.constant.value
          super_class_name = node.superclass.value.value

          add_tip(range, "#{class_name} < #{super_class_name}", 0o0001, <<~TIP)
            The class #{class_name} inherits from #{super_class_name}.

            All methods defined in the superclass (#{super_class_name}) are available in the subclass (#{class_name}).
          TIP
        end

        super
      end

      private

      sig { params(range: Interface::Range, value: String, code: Integer, message: String).void }
      def add_tip(range, value, code, message)
        @tips << Interface::Diagnostic.new(
          message: message,
          source: "Tips",
          severity: Constant::DiagnosticSeverity::INFORMATION,
          range: range,
          code: code,
          data: {
            correctable: true,
            code_action: Interface::CodeAction.new(
              title: "Learned it!",
              kind: Constant::CodeActionKind::QUICK_FIX,
              edit: Interface::WorkspaceEdit.new(
                document_changes: [
                  Interface::TextDocumentEdit.new(
                    text_document: Interface::OptionalVersionedTextDocumentIdentifier.new(
                      uri: @uri,
                      version: nil,
                    ),
                    edits: [Interface::TextEdit.new(range: range, new_text: value)],
                  ),
                ],
              ),
              is_preferred: true,
            ),
          },
        )
      end
    end
  end
end
