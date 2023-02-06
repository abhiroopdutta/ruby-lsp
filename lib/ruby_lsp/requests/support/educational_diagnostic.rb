# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      class EducationalDiagnostic
        extend T::Sig

        sig { returns(T::Array[LanguageServer::Protocol::Interface::TextEdit]) }
        attr_reader :replacements

        sig { params(message: String, range: LanguageServer::Protocol::Interface::Range).void }
        def initialize(message, range)
          @message = message
          @range = range
          @replacements = T.let([], T::Array[LanguageServer::Protocol::Interface::TextEdit])
        end

        sig { returns(T::Boolean) }
        def correctable?
          false
        end

        sig { returns(LanguageServer::Protocol::Interface::CodeAction) }
        def to_lsp_code_action
          # TODO: Implement this
          # LanguageServer::Protocol::Interface::CodeAction.new(
          #   title: "Autocorrect #{@offense.cop_name}",
          #   kind: LanguageServer::Protocol::Constant::CodeActionKind::QUICK_FIX,
          #   edit: LanguageServer::Protocol::Interface::WorkspaceEdit.new(
          #     document_changes: [
          #       LanguageServer::Protocol::Interface::TextDocumentEdit.new(
          #         text_document: LanguageServer::Protocol::Interface::OptionalVersionedTextDocumentIdentifier.new(
          #           uri: @uri,
          #           version: nil,
          #         ),
          #         edits: @replacements,
          #       ),
          #     ],
          #   ),
          #   is_preferred: true,
          # )
        end

        sig { returns(LanguageServer::Protocol::Interface::Diagnostic) }
        def to_lsp_diagnostic
          LanguageServer::Protocol::Interface::Diagnostic.new(
            message: @message,
            source: "Education",
            severity: LanguageServer::Protocol::Constant::DiagnosticSeverity::INFORMATION,
            range: @range,
          )
        end
      end
    end
  end
end
