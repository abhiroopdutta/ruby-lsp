# typed: strict
# frozen_string_literal: true

# Things to keep in mind
# - Allow adding middleware from gems
# - Allow adding middleware from the project
# - Allow adding middleware from the user's home directory
# - Make it easy to handle empty base responses (think about request hierarchy and interfaces)
# - Think about middleware ordering and dependencies (see https://en.wikipedia.org/wiki/Partially_ordered_set)
#   - dependency(after: :rails)
#   - dependency(before: :base)
# - Provide guidance that the more middleware added, the slower the server will be
# - Think about how to allow plugins to define requests we don't yet implement
#   - How do we know what to pass to the request?

module RubyLsp
  module Middleware
    class Hover
      extend T::Sig
      extend T::Helpers

      class << self
        extend T::Sig

        sig { returns(T::Array[T.class_of(Hover)]) }
        def middleware_classes
          @middleware_classes || []
        end

        sig { params(child_class: T.class_of(Hover)).void }
        def inherited(child_class)
          @middleware_classes ||= T.let([], T.nilable(T::Array[T.class_of(Hover)]))
          @middleware_classes << child_class

          super
        end
      end

      abstract!

      sig { params(document: Document, position: Document::PositionShape).void }
      def initialize(document, position)
        @document = document
        @position = T.let(document.create_scanner.find_char_position(position), Integer)
        target, parent = locate(T.must(@document.tree), @position)

        @target = T.let(target, T.nilable(SyntaxTree::Node))
        @parent = T.let(parent, T.nilable(SyntaxTree::Node))
      end

      sig { abstract.params(response: T.nilable(Interface::Hover)).returns(T.nilable(Interface::Hover)) }
      def run(response); end

      sig do
        params(
          node: SyntaxTree::Node,
          position: Integer,
        ).returns([T.nilable(SyntaxTree::Node), T.nilable(SyntaxTree::Node)])
      end
      def locate(node, position)
        queue = T.let(node.child_nodes.compact, T::Array[T.nilable(SyntaxTree::Node)])
        closest = node

        until queue.empty?
          candidate = queue.shift

          # Skip nil child nodes
          next if candidate.nil?

          # Add the next child_nodes to the queue to be processed
          queue.concat(candidate.child_nodes)

          # Skip if the current node doesn't cover the desired position
          loc = candidate.location
          next unless (loc.start_char...loc.end_char).cover?(position)

          # If the node's start character is already past the position, then we should've found the closest node already
          break if position < loc.start_char

          # If the current node is narrower than or equal to the previous closest node, then it is more precise
          closest_loc = closest.location
          if loc.end_char - loc.start_char <= closest_loc.end_char - closest_loc.start_char
            parent = T.let(closest, SyntaxTree::Node)
            closest = candidate
          end
        end

        [closest, parent]
      end

      sig { params(node: SyntaxTree::Node).returns(Interface::Range) }
      def range_from_syntax_tree_node(node)
        loc = node.location

        Interface::Range.new(
          start: Interface::Position.new(
            line: loc.start_line - 1,
            character: loc.start_column,
          ),
          end: Interface::Position.new(line: loc.end_line - 1, character: loc.end_column),
        )
      end

      sig { returns(Interface::Hover) }
      def empty_response
        contents = Interface::MarkupContent.new(
          kind: "markdown",
          value: +"",
        )
        Interface::Hover.new(
          range: range_from_syntax_tree_node(T.must(@target)),
          contents: contents,
        )
      end
    end
  end
end
