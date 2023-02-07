# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    # ![Code actions demo](../../misc/code_actions.gif)
    #
    # The [code actions](https://microsoft.github.io/language-server-protocol/specification#textDocument_codeAction)
    # request informs the editor of RuboCop quick fixes that can be applied. These are accessible by hovering over a
    # specific diagnostic.
    #
    # # Example
    #
    # ```ruby
    # def say_hello
    # puts "Hello" # --> code action: quick fix indentation
    # end
    # ```
    class CodeActions < BaseRequest
      extend T::Sig

      sig do
        params(
          uri: String,
          document: Document,
          range: T::Range[Integer],
          context: T::Hash[Symbol, T.untyped],
        ).void
      end
      def initialize(uri, document, range, context)
        super(document)

        @uri = uri
        @range = range
        @context = context
      end

      sig { override.returns(T.nilable(T.all(T::Array[Interface::CodeAction], Object))) }
      def run
        diagnostics = @context[:diagnostics]
        return if diagnostics.nil? || diagnostics.empty?

        diagnostics.filter_map do |diagnostic|
          code_action = diagnostic.dig(:data, :code_action)
          range = code_action.dig(:edit, :documentChanges, 0, :edits, 0, :range)

          if diagnostic.dig(:data, :correctable) && @range.cover?(range.dig(:start, :line)..range.dig(:end, :line))
            code_action
          end
        end
      end
    end
  end
end
