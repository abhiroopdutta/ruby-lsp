# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Extensions
    # The extension class is the entry point for Ruby LSP extensions. Each extension should have a single class
    # inheriting from this one. The class should be named after the extension and should be placed under
    # `lib/ruby_lsp/my_extension_name.rb`, which will be required automatically by the Ruby LSP. Additionally, the file
    # should require any other parts of your extension, such as middleware.
    #
    # As an example, the extension structure could look like this:
    # - lib
    #   - ruby_lsp
    #     - extension.rb
    #   - middleware
    #     - hover.rb
    class Extension
      extend T::Helpers

      abstract!

      class << self
        extend T::Sig

        sig { returns(T::Array[T.class_of(Extension)]) }
        def extensions
          @extensions ||= T.let([], T.nilable(T::Array[T.class_of(Extension)]))
        end

        # Extensions are registered automatically by inheriting from this base class
        sig { params(child_class: T.class_of(Extension)).void }
        def inherited(child_class)
          extensions << child_class
          super
        end

        # If the extension needs to perform any sort of initialization, like booting a separate process or reading files
        # into memory, it should implement the `activate` method. Doing so will ensure that the Ruby LSP activates the
        # extensions at the most convenient time without blocking users
        sig { abstract.void }
        def activate; end
      end
    end
  end
end
