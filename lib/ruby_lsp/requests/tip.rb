# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    class Tip < BaseRequest
      extend T::Sig

      TIPS = T.let(
        YAML.load(File.read(File.expand_path("support/tips.yml", __dir__))).freeze,
        T::Hash[String, T.untyped],
      )

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
          class_name = node_name(node.constant)
          super_class_name = node_name(node.superclass)
          code, message = fetch_tip("superclass", { class_name: class_name, super_class_name: super_class_name })

          add_tip(range, "#{class_name} < #{super_class_name}", code, message)
        end

        super
      end

      sig { params(node: SyntaxTree::Command).void }
      def visit_command(node)
        range = range_from_syntax_tree_node(node.message)
        value = node.message.value

        case value
        when "validate"
          method_name = node_name(node.arguments.parts.first)
          code, message = fetch_tip("validate", { method_name: method_name })

          add_tip(range, value, code, message)
        when "validates"
          field_name = node_name(node.arguments.parts.first)
          code, message = fetch_tip("validates", { field_name: field_name })

          add_tip(range, value, code, message)
        end

        super
      end

      sig { params(node: SyntaxTree::DefNode).void }
      def visit_def(node)
        method_name = node_name(node)

        case method_name
        when "method_missing"
          range = range_from_syntax_tree_node(node.name)
          code, message = fetch_tip("method_missing")

          add_tip(range, method_name, code, message)
        end

        super
      end

      private

      sig do
        params(range: Interface::Range, value: T.nilable(String), code: T.any(Integer, String), message: String).void
      end
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

      sig do
        params(key: String, replacements: T.nilable(T::Hash[String, String])).returns([Integer, String])
      end
      def fetch_tip(key, replacements = nil)
        [
          TIPS.dig(key, "code"),
          format(TIPS.dig(key, "message"), replacements),
        ]
      end

      sig do
        params(node: T.nilable(T.any(
          SyntaxTree::VarRef,
          SyntaxTree::ConstRef,
          SyntaxTree::DefNode,
          SyntaxTree::CallNode,
          SyntaxTree::VCall,
          SyntaxTree::Ident,
          SyntaxTree::Backtick,
          SyntaxTree::Const,
          SyntaxTree::Op,
          SyntaxTree::SymbolLiteral,
          Symbol,
        ))).returns(T.nilable(String))
      end
      def node_name(node)
        case node
        when NilClass
          nil
        when SyntaxTree::VarRef
          node.value.value
        when SyntaxTree::ConstRef
          node_name(node.constant)
        when SyntaxTree::DefNode
          node_name(node.name)
        when SyntaxTree::CallNode
          node_name(node.receiver)
        when SyntaxTree::VCall, SyntaxTree::SymbolLiteral
          node_name(node.value)
        when SyntaxTree::Ident, SyntaxTree::Backtick, SyntaxTree::Const, SyntaxTree::Op
          node.value
        when Symbol
          node.to_s
        else
          T.absurd(node)
        end
      end
    end
  end
end
