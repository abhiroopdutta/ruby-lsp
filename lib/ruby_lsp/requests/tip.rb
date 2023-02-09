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

        TIPS.each do |key, tip|
          next unless tip["search_pattern"]

          SyntaxTree.search(@document.source, tip["search_pattern"]) do |node|
            range = range_from_methods(tip.fetch("range", []), node)
            next if range.nil?

            template_variables = tip.fetch("extraction_methods", []).each_with_object({}) do |(name, chain), hash|
              matched_node = run_method_chain(chain, node)
              hash[name.to_sym] = node_name(matched_node)
            end

            message = format(tip["message"], template_variables)
            text = replacement_text(range)

            add_tip(range, text, tip["code"], message)
          end
        rescue StandardError => e
          warn("Failed to parse tip: #{key}: #{e}")
        end

        @tips
      end

      private

      sig { params(range: Interface::Range).returns(String) }
      def replacement_text(range)
        lines = @document.source.split("\n").map(&:chars)
        value = T.must(lines[range.start.line..range.end.line])
        (T.must(value[-1]).size - range.end.character).times { T.must(value[-1]).pop }
        range.start.character.times { T.must(value[0]).shift }
        value.map(&:join).join("\n")
      end

      sig { params(range_methods: T::Array[String], node: SyntaxTree::Node).returns(T.nilable(Interface::Range)) }
      def range_from_methods(range_methods, node)
        return if range_methods.empty?
        return unless [1, 2].include?(range_methods.size)

        method_chain_from, method_chain_to = range_methods

        if range_methods.size == 1
          matched_node = run_method_chain(method_chain_from, node)

          range_from_syntax_tree_node(matched_node)
        else
          from_matched_node = run_method_chain(method_chain_from, node)
          to_matched_node = run_method_chain(method_chain_to, node)

          range_between_nodes(from_matched_node, to_matched_node)
        end
      end

      sig { params(methods: T.nilable(String), node: SyntaxTree::Node).returns(SyntaxTree::Node) }
      def run_method_chain(methods, node)
        return node if methods.nil?

        methods.split(".").reduce(node) do |acc, method|
          acc.public_send(method)
        end
      end

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
        params(node: T.nilable(T.any(
          SyntaxTree::Node,
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
        when SyntaxTree::Node
          # SyntaxTree::Node is a superclass of all the above.
        else
          T.absurd(node)
        end
      end
    end
  end
end
