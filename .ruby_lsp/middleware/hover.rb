# typed: strict
# frozen_string_literal: true

module Rails
  class Hover < RubyLsp::Middleware::Hover
    sig do
      override.params(response: T.nilable(RubyLsp::Interface::Hover)).returns(T.nilable(RubyLsp::Interface::Hover))
    end
    def run(response)
      response = empty_response unless response
      response.contents.value.prepend("Hello from our middleware!!!")
      response
    end
  end
end
