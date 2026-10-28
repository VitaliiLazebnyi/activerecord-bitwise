# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/conditions'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Prepended to ActiveRecord::Relation to make batch updates and hash queries
    # understand bitwise flag arrays.
    module RelationExtension
      extend T::Sig

      # Intercepts update_all to convert bitwise attribute arrays into a
      # ghost-bit-preserving SQL expression: `(COALESCE(col, 0) & ~known_mask) | mask`.
      # Unmapped ("forgotten") bits of every matched row are preserved, matching the
      # behavior of instance-level saves.
      # @raise [UnknownValueError] If the assigned array contains values missing from the mapping.
      # @param updates [T.untyped]
      # @return [T.untyped]
      sig { params(updates: T.untyped).returns(T.untyped) }
      def update_all(updates)
        return super unless (updates in Hash) && T.unsafe(self).klass.respond_to?(:bitwise_definitions)

        super(Conditions.assignments(T.unsafe(self).klass, updates))
      end

      # Intercepts where to transparently serialize bitwise flag arrays into their
      # integer bitmask (exact-match semantics, like Rails' native enum). This keeps
      # ordinary ActiveRecord idioms (`where`, `find_by`, uniqueness validators)
      # working instead of raising.
      # @note Use the generated `with_*`/`without_*` scopes for subset/superset matching;
      #   a hash condition matches the exact bitmask only.
      # @param args [T.untyped]
      # @return [T.untyped]
      sig { params(args: T.untyped).returns(T.untyped) }
      def where(*args)
        if (args.first in Hash) && T.unsafe(self).klass.respond_to?(:bitwise_definitions)
          args[0] = Conditions.serialize(T.unsafe(self).klass, T.unsafe(args.first))
        end
        super
      end
    end

    # Prepended to ActiveRecord::QueryMethods::WhereChain to serialize negated
    # bitwise hash conditions the same way as {RelationExtension#where}.
    module WhereChainExtension
      extend T::Sig

      # Intercepts not to transparently serialize bitwise flag arrays.
      # @param args [T.untyped]
      # @return [T.untyped]
      sig { params(args: T.untyped).returns(T.untyped) }
      def not(*args)
        scope = T.unsafe(self).instance_variable_get(:@scope)
        if (args.first in Hash) && scope && T.unsafe(scope).klass.respond_to?(:bitwise_definitions)
          args[0] = Conditions.serialize(T.unsafe(scope).klass, T.unsafe(args.first))
        end
        super
      end
    end
  end
end
