# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Extensions
    autoload :Extension, "ruby_lsp/extensions/extension"

    module Middleware
      autoload :Hover, "ruby_lsp/extensions/middleware/hover"
    end
  end
end
