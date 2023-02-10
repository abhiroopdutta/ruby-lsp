# typed: strict
# frozen_string_literal: true

require "ruby_test_runner"

module RubyLsp
  module Requests
    # ![Code lens demo](../../misc/code_actions.gif)
    #
    # The [code lens](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeLens)
    # represents a command that should be shown along with source text, like the number of references, a way to run
    # tests, etc.
    #
    # # Example
    #
    # ```ruby
    # # A text shows up here that will run the test when clicked.
    # def test_it_works
    #   assert true
    # end
    # ```
    class CodeLens < BaseRequest
      RUN_TEST_COMMAND = "rubyLsp.runTest"

      sig { params(document: Document, uri: String).void }
      def initialize(document, uri)
        super(document)

        @uri = uri
        @code_lenses = T.let([], T::Array[Interface::CodeLens])
      end

      sig { override.returns(T.all(T::Array[Interface::CodeLens], Object)) }
      def run
        visit(@document.tree) if @document.parsed?
        @code_lenses
      end

      sig { override.params(node: SyntaxTree::DefNode).void }
      def visit_def(node)
        super
        name = node.name.value
        return unless name.start_with?("test_")

        @code_lenses << code_lens_for_single_test(node, name)
      end

      sig { override.params(node: SyntaxTree::ClassDeclaration).void }
      def visit_class(node)
        super
        name = node.constant.constant.value
        return unless name.end_with?("Test")

        @code_lenses << code_lens_for_all_tests_in_file(node)
      end

      private

      sig { params(node: SyntaxTree::DefNode, name: String).returns(Interface::CodeLens) }
      def code_lens_for_single_test(node, name)
        path = @uri.delete_prefix("file://")

        Interface::CodeLens.new(
          range: range_from_syntax_tree_node(node),
          command: Interface::Command.new(
            command: RUN_TEST_COMMAND, title: "🔍 Run this test", arguments: [path, name],
          ),
        )
      end

      sig { params(node: SyntaxTree::ClassDeclaration).returns(Interface::CodeLens) }
      def code_lens_for_all_tests_in_file(node)
        path = @uri.delete_prefix("file://#{Dir.pwd}/")
        command = RubyTestRunner::Command.new(Dir.pwd, path, nil).runner_command

        Interface::CodeLens.new(
          range: range_from_syntax_tree_node(node),
          command: Interface::Command.new(
            command: RUN_TEST_COMMAND, title: "✨ Run all tests in this file ✨", arguments: [command],
          ),
        )
      end
    end
  end
end
