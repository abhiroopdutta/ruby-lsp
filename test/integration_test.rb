# typed: true
# frozen_string_literal: true

require "test_helper"
require "open3"
require "timeout"

# Important integration test notes
#
# 1. If the request returns `nil`, use `send_request` and do not try to read the response or else it times out
# 2. Make sure the request name is exactly the expected in CLI (e.g.: textDocument/foldingRange instead of
# textDocument/foldingRanges). If the name is incorrect, the LSP won't return anything reading the response will timeout
# 3. The goal is to verify that all parts are working together. Don't create extensive tests with long code examples -
# those are meant for unit tests
class IntegrationTest < Minitest::Test
  FEATURE_TO_PROVIDER = {
    "documentHighlights" => :documentHighlightProvider,
    "documentLink" => :documentLinkProvider,
    "documentSymbols" => :documentSymbolProvider,
    "foldingRanges" => :foldingRangeProvider,
    "selectionRanges" => :selectionRangeProvider,
    "semanticHighlighting" => :semanticTokensProvider,
    "formatting" => :documentFormattingProvider,
    "onTypeFormatting" => :documentOnTypeFormattingProvider,
    "codeActions" => :codeActionProvider,
    "diagnostics" => :diagnosticProvider,
    "hover" => :hoverProvider,
    "codeLens" => :codeLensProvider,
  }.freeze

  def setup
    if RUBY_PLATFORM.match?(/(mswin|mingw)/)
      skip("Skipping for Windows: https://github.com/Shopify/ruby-lsp/issues/751")
    end
    # Start a new Ruby LSP server in a separate process and set the IOs to binary mode
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3("bundle exec ruby-lsp")
  end

  def teardown
    # Tell the LSP to shutdown
    make_request("shutdown")
    send_request("exit")

    # Make sure IOs are closed
    @stdin.close
    @stdout.close
    @stderr.close

    # Make sure the exit status is zero
    assert_equal(0, @wait_thr.value)
    refute_predicate(@wait_thr, :alive?)
  end

  def test_document_symbol
    initialize_lsp(["documentSymbols"])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request("textDocument/documentSymbol", { textDocument: { uri: "file://#{__FILE__}" } })
    symbol = response[:result].first
    assert_equal("Foo", symbol[:name])
    assert_equal(RubyLsp::Requests::DocumentSymbol::SYMBOL_KIND[:class], symbol[:kind])
  end

  def test_document_highlight
    initialize_lsp(["documentHighlights"])
    open_file_with("$foo = 1")

    assert_telemetry("textDocument/didOpen")

    response = make_request(
      "textDocument/documentHighlight",
      { textDocument: { uri: "file://#{__FILE__}" }, position: { line: 0, character: 1 } },
    )

    range = response[:result].first
    assert_equal(LanguageServer::Protocol::Constant::DocumentHighlightKind::WRITE, range[:kind])
  end

  def test_hover
    initialize_lsp(["hover"])
    open_file_with("$foo = 1")

    assert_telemetry("textDocument/didOpen")

    response = make_request(
      "textDocument/hover",
      { textDocument: { uri: "file://#{__FILE__}" }, position: { line: 0, character: 1 } },
    )

    assert_nil(response[:result])
    assert_nil(response[:error])
  end

  def test_document_highlight_with_syntax_error
    initialize_lsp(["documentHighlights"])
    open_file_with("class Foo")

    response = make_request(
      "textDocument/documentHighlight",
      { textDocument: { uri: "file://#{__FILE__}" }, position: { line: 0, character: 1 } },
    )

    assert_nil(response[:result])
    assert_nil(response[:error])
  end

  def test_semantic_highlighting
    initialize_lsp(["semanticHighlighting"])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request("textDocument/semanticTokens/full", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_equal([0, 6, 3, 2, 1], response[:result][:data])
  end

  def test_document_link
    initialize_lsp(["documentLink"])
    open_file_with(<<~DOC)
      # source://syntax_tree/#{Gem::Specification.find_by_name("syntax_tree").version}/lib/syntax_tree.rb#39
      def foo
      end
    DOC

    assert_telemetry("textDocument/didOpen")

    response = make_request("textDocument/documentLink", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_match(/syntax_tree/, response.dig(:result, 0, :target))
  end

  def test_formatting
    initialize_lsp(["formatting"])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request("textDocument/formatting", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_equal(<<~FORMATTED, response[:result].first[:newText])
      # typed: true
      # frozen_string_literal: true

      class Foo
      end
    FORMATTED
  end

  def test_on_type_formatting
    initialize_lsp(["onTypeFormatting"])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request(
      "textDocument/onTypeFormatting",
      { textDocument: { uri: "file://#{__FILE__}", position: { line: 0, character: 0 }, character: "\n" } },
    )
    assert_nil(response[:result])
  end

  def test_code_actions
    initialize_lsp(["codeActions"])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request(
      "textDocument/codeAction",
      {
        textDocument: { uri: "file://#{__FILE__}" },
        range: { start: { line: 2 }, end: { line: 4 } },
        context: {
          diagnostics: [
            {
              range: {
                start: { line: 2, character: 0 },
                end: { line: 2, character: 0 },
              },
              message: "Layout/EmptyLines: Extra blank line detected.",
              data: {
                correctable: true,
                code_action: {
                  title: "Autocorrect Layout/EmptyLines",
                  kind: "quickfix",
                  isPreferred: true,
                  edit: {
                    documentChanges: [
                      {
                        textDocument: { uri: "file://#{__FILE__}", version: nil },
                        edits: [
                          {
                            range: {
                              start: { line: 2, character: 0 },
                              end: { line: 3, character: 0 },
                            },
                            newText: "",
                          },
                        ],
                      },
                    ],
                  },
                },
              },
              code: "Layout/EmptyLines",
              severity: 3,
              source: "RuboCop",
            },
          ],
        },
      },
    )
    quickfix = response[:result].detect { |action| action[:kind] == "quickfix" }
    assert(quickfix)
    assert_match(%r{Autocorrect .*/.*}, quickfix[:title])
  end

  def test_code_action_resolve
    initialize_lsp(["codeActions"])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request(
      "codeAction/resolve",
      {
        kind: "refactor.extract",
        data: {
          range: { start: { line: 1, character: 1 }, end: { line: 1, character: 3 } },
          uri: "file://#{__FILE__}",
        },
      },
    )
    assert_equal("Refactor: Extract Variable", response[:result][:title])
  end

  def test_document_did_close
    initialize_lsp([])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    assert(send_request("textDocument/didClose", { textDocument: { uri: "file://#{__FILE__}" } }))
  end

  def test_document_did_change
    initialize_lsp([])
    open_file_with("class Foo\nend")

    assert(send_request(
      "textDocument/didChange",
      {
        textDocument: { uri: "file://#{__FILE__}" },
        contentChanges: [{
          text: "class Foo\ndef bar\nend\nend",
          range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } },
        }],
      },
    ))
  end

  def test_folding_ranges
    initialize_lsp(["foldingRanges"])
    open_file_with("class Foo\n\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request("textDocument/foldingRange", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_equal({ startLine: 0, endLine: 1, kind: "region" }, response[:result].first)
  end

  def test_code_lens
    initialize_lsp(["codeLens"], experimental_features_enabled: true)
    open_file_with("class Foo\n\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request("textDocument/codeLens", { textDocument: { uri: "file://#{__FILE__}" } })
    assert_empty(response[:result])
  end

  def test_request_with_telemetry
    initialize_lsp(["foldingRanges"])
    open_file_with("class Foo\n\nend")

    send_request("textDocument/foldingRange", { textDocument: { uri: "file://#{__FILE__}" } })

    assert_telemetry("textDocument/didOpen")

    response = read_response("textDocument/foldingRange")
    assert_equal({ startLine: 0, endLine: 1, kind: "region" }, response[:result].first)
    assert_telemetry("textDocument/foldingRange")
  end

  def test_selection_ranges
    initialize_lsp(["selectionRanges"])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request(
      "textDocument/selectionRange",
      {
        textDocument: { uri: "file://#{__FILE__}" },
        positions: [{ line: 0, character: 0 }],
      },
    )

    assert_equal(
      { range: { start: { line: 0, character: 0 }, end: { line: 1, character: 3 } } },
      response[:result].first,
    )
  end

  def test_selection_ranges_with_syntax_error
    initialize_lsp(["selectionRanges"])
    open_file_with("class Foo")

    response = make_request(
      "textDocument/selectionRange",
      {
        textDocument: { uri: "file://#{__FILE__}" },
        positions: [{ line: 0, character: 0 }],
      },
    )

    assert_nil(response[:result])
    assert_nil(response[:error])
  end

  def test_diagnostics
    initialize_lsp([])
    open_file_with("class Foo\nend")

    assert_telemetry("textDocument/didOpen")

    response = make_request("textDocument/diagnostic", { textDocument: { uri: "file://#{__FILE__}" } })

    assert_equal("full", response.dig(:result, :kind))
    assert_equal("Sorbet/TrueSigil", response.dig(:result, :items)[0][:code])
  end

  private

  def assert_telemetry(request)
    telemetry_response = read_response("telemetry/event")
    expected_uri = __FILE__.sub(Dir.home, "~")

    assert_equal(expected_uri, telemetry_response.dig(:params, :uri))
    assert_equal(RubyLsp::VERSION, telemetry_response.dig(:params, :lspVersion))
    assert_equal(request, telemetry_response.dig(:params, :request))
    assert_in_delta(0.5, telemetry_response.dig(:params, :requestTime), 2)
  end

  def make_request(request, params = nil)
    send_request(request, params)
    read_response(request)
  end

  def read_response(request)
    timeout_amount = ENV["CI"] ? 20 : 5

    Timeout.timeout(timeout_amount) do
      # Read headers until line breaks
      headers = @stdout.gets("\r\n\r\n")
      # Read the response content based on the length received in the headers
      raw_response = @stdout.read(headers[/Content-Length: (\d+)/i, 1].to_i)
      JSON.parse(raw_response, symbolize_names: true)
    end
  rescue Timeout::Error
    raise "Request #{request} timed out. Is the request returning a response?"
  end

  def send_request(request, params = nil)
    hash = {
      jsonrpc: "2.0",
      id: rand(100),
      method: request,
    }

    hash[:params] = params if params
    json = hash.to_json
    @stdin.write("Content-Length: #{json.length}\r\n\r\n#{json}")
  end

  def initialize_lsp(enabled_features, experimental_features_enabled: false)
    response = make_request(
      "initialize",
      {
        initializationOptions: {
          enabledFeatures: enabled_features,
          experimentalFeaturesEnabled: experimental_features_enabled,
          formatter: "rubocop",
        },
      },
    )[:result]

    assert(true, response.dig(:capabilities, :textDocumentSync, :openClose))
    assert(
      LanguageServer::Protocol::Constant::TextDocumentSyncKind::INCREMENTAL,
      response.dig(:capabilities, :textDocumentSync, :openClose),
    )

    enabled_features.each do |feature|
      assert(response.dig(:capabilities, FEATURE_TO_PROVIDER[feature]))
    end

    enabled_providers = enabled_features.map { |feature| FEATURE_TO_PROVIDER[feature] }
    assert_equal([:positionEncoding, :textDocumentSync, *enabled_providers], response[:capabilities].keys)
  end

  def open_file_with(content)
    make_request("textDocument/didOpen", { textDocument: { uri: "file://#{__FILE__}", text: content } })
  end
end
