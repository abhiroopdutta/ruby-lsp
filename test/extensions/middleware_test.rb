# typed: true
# frozen_string_literal: true

require "test_helper"

class MiddlewareTest < Minitest::Test
  def setup
    @middleware = Class.new(RubyLsp::Extensions::Middleware::Hover) do
      def run
        response = T.let(@response, RubyLsp::Interface::Hover)
        response.contents.value.prepend("Hello from middleware! ")
        response
      end
    end
  end

  def test_run_middleware_combines_responses
    document = RubyLsp::Document.new(<<~RUBY)
      class Foo
      end
    RUBY

    contents = LanguageServer::Protocol::Interface::MarkupContent.new(kind: "markdown", value: +"Some intial content")
    hover = LanguageServer::Protocol::Interface::Hover.new(
      range: LanguageServer::Protocol::Interface::Range.new(
        start: LanguageServer::Protocol::Interface::Position.new(line: 0, character: 6),
        end: LanguageServer::Protocol::Interface::Position.new(line: 0, character: 9),
      ),
      contents: contents,
    )

    response = T.must(
      RubyLsp::Requests::Hover.run_middleware(
        document,
        { line: 0, character: 6 },
        hover,
      ),
    )

    assert_equal("Hello from middleware! Some intial content", response.contents.value)
  end
end
