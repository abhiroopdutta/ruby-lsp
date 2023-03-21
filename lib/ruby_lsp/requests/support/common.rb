# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Requests
    module Support
      module Common
        extend T::Sig
        extend T::Helpers

        requires_ancestor { SyntaxTree::Visitor }

        # Syntax Tree implements `visit_all` using `map` instead of `each` for users who want to use the pattern
        # `result = visitor.visit(tree)`. However, we don't use that pattern and should avoid producing a new array for
        # every single node visited
        sig { params(nodes: T::Array[SyntaxTree::Node]).void }
        def visit_all(nodes)
          nodes.each { |node| visit(node) }
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

        sig do
          params(node: T.any(SyntaxTree::ConstPathRef, SyntaxTree::ConstRef, SyntaxTree::TopConstRef)).returns(String)
        end
        def full_constant_name(node)
          name = +node.constant.value
          constant = T.let(node, SyntaxTree::Node)

          while constant.is_a?(SyntaxTree::ConstPathRef)
            constant = constant.parent

            case constant
            when SyntaxTree::ConstPathRef
              name.prepend("#{constant.constant.value}::")
            when SyntaxTree::VarRef
              name.prepend("#{constant.value.value}::")
            end
          end

          name
        end

        sig do
          params(
            node: SyntaxTree::Node,
            position: Integer,
            node_types: T::Array[T.class_of(SyntaxTree::Node)],
          ).returns([T.nilable(SyntaxTree::Node), T.nilable(SyntaxTree::Node)])
        end
        def locate(node, position, node_types: [])
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

            # If the node's start character is already past the position, then we should've found the closest node
            # already
            break if position < loc.start_char

            # If there are node types to filter by, and the current node is not one of those types, then skip it
            next if node_types.any? && node_types.none? { |type| candidate.is_a?(type) }

            # If the current node is narrower than or equal to the previous closest node, then it is more precise
            closest_loc = closest.location
            if loc.end_char - loc.start_char <= closest_loc.end_char - closest_loc.start_char
              parent = T.let(closest, SyntaxTree::Node)
              closest = candidate
            end
          end

          [closest, parent]
        end

        sig { params(node: T.nilable(SyntaxTree::Node), range: T.nilable(T::Range[Integer])).returns(T::Boolean) }
        def visible?(node, range)
          return true if range.nil?
          return false if node.nil?

          loc = node.location
          range.cover?(loc.start_line - 1) && range.cover?(loc.end_line - 1)
        end
      end
    end
  end
end
