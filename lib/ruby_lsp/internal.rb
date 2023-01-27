# typed: strict
# frozen_string_literal: true

require "sorbet-runtime"
require "syntax_tree"
require "language_server-protocol"
require "benchmark"

require "ruby-lsp"
require "ruby_lsp/utils"
require "ruby_lsp/server"
require "ruby_lsp/executor"
require "ruby_lsp/requests"
require "ruby_lsp/store"

require "ruby_lsp/middleware/hover"

# Should we allow for multiple middleware for the same feature in the same project?
Dir[".ruby_lsp/middleware/**/*.rb"].each { |file| require(File.expand_path(file)) }
