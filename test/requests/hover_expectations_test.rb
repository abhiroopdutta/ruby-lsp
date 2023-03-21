# typed: true
# frozen_string_literal: true

require "test_helper"
require "net/http" # for stubbing
require "expectations/expectations_test_runner"

class HoverExpectationsTest < ExpectationsTestRunner
  expectations_tests RubyLsp::Requests::Hover, "hover"

  def assert_expectations(source, expected)
    source = substitute(source)
    actual = T.cast(run_expectations(source), T.nilable(LanguageServer::Protocol::Interface::Hover))
    actual_json = actual ? JSON.parse(actual.to_json) : nil
    assert_equal(json_expectations(substitute(expected)), actual_json)
  end

  def test_search_index_being_nil
    document = RubyLsp::Document.new("belongs_to :foo")

    RubyLsp::Requests::Support::RailsDocumentClient.stubs(search_index: nil)
    RubyLsp::Requests::Hover.new(document, { character: 0, line: 0 }).run
  end

  class FakeHTTPResponse
    attr_reader :code, :body

    def initialize(code, body)
      @code = code
      @body = body
    end
  end

  def run_expectations(source)
    document = RubyLsp::Document.new(source)
    js_content = File.read(File.join(TEST_FIXTURES_DIR, "rails_search_index.js"))
    fake_response = FakeHTTPResponse.new("200", js_content)

    position = @__params&.first || { character: 0, line: 0 }

    Net::HTTP.stubs(get_response: fake_response)
    RubyLsp::Requests::Hover.new(document, position).run
  end

  def test_after_request_hook
    RubyLsp::Requests::Hover.after_request(after_request_visitor)
    js_content = File.read(File.join(TEST_FIXTURES_DIR, "rails_search_index.js"))
    fake_response = FakeHTTPResponse.new("200", js_content)
    Net::HTTP.stubs(get_response: fake_response)

    document = RubyLsp::Document.new(<<~RUBY)
      class Post
        belongs_to :user
      end
    RUBY

    response = T.cast(
      RubyLsp::Requests::Hover.new(document, { line: 1, character: 2 }).run_request,
      RubyLsp::Interface::Hover,
    )

    assert_match("Method from middleware: belongs_to", response.contents.value)
    assert_match("[Rails Document: `ActiveRecord::Associations::ClassMethods#belongs_to`]", response.contents.value)
  ensure
    RubyLsp::Requests::Hover.after_request_hooks.clear
  end

  private

  def after_request_visitor
    Class.new(RubyLsp::Extensions::Visitor) do
      def initialize(**kwargs)
        @response = T.let(kwargs[:response], RubyLsp::Interface::Hover)
        @document = kwargs[:document]
        @position = kwargs[:position]
        @target = T.let(kwargs[:target], SyntaxTree::Command)

        super
      end

      def run
        @response.contents.value.prepend("Method from middleware: #{@target.message.value} ")
        @response
      end
    end
  end

  def substitute(original)
    original.gsub("RAILTIES_VERSION", Gem::Specification.find_by_name("railties").version.to_s)
  end
end
