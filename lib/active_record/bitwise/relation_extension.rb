# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/conditions'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Prepended to ActiveRecord::Relation to make batch updates and hash queries
    # understand bitwise flag arrays.
    module RelationExtension
      extend T::Sig
      extend T::Helpers

      requires_ancestor { ActiveRecord::Relation }

      # Intercepts update_all to convert bitwise attribute arrays into a
      # ghost-bit-preserving SQL expression: `(COALESCE(col, 0) & ~known_mask) | mask`.
      # Unmapped ("forgotten") bits of every matched row are preserved, matching the
      # behavior of instance-level saves.
      # @raise [UnknownValueError] If the assigned array contains values missing from the mapping.
      # @param updates [Object] The assignments.
      # @return [Integer] The number of updated rows.
      sig { params(updates: Object).returns(Integer) }
      def update_all(updates)
        return super unless updates.is_a?(Hash)

        super(Conditions.assignments(klass, updates))
      end

      # Intercepts where to transparently serialize bitwise flag arrays into their
      # integer bitmask (exact-match semantics, like Rails' native enum). This keeps
      # ordinary ActiveRecord idioms (`where`, `find_by`, uniqueness validators)
      # working instead of raising.
      # @note Use the generated `with_*`/`without_*` scopes for subset/superset matching;
      #   a hash condition matches the exact bitmask only.
      # @param args [Array<Object>] The conditions.
      # @return [ActiveRecord::Relation, ActiveRecord::QueryMethods::WhereChain]
      sig { params(args: Object).returns(T.any(ActiveRecord::Relation, ActiveRecord::QueryMethods::WhereChain)) }
      def where(*args)
        args = Conditions.arguments(klass, args)
        super
      end
    end

    # Prepended to ActiveRecord::QueryMethods::WhereChain to serialize negated
    # bitwise hash conditions the same way as RelationExtension#where.
    module WhereChainExtension
      extend T::Sig
      extend T::Helpers

      requires_ancestor { ActiveRecord::QueryMethods::WhereChain }

      # Intercepts not to transparently serialize bitwise flag arrays.
      # @param args [Array<Object>] The conditions.
      # @return [ActiveRecord::Relation]
      sig { params(args: Object).returns(ActiveRecord::Relation) }
      def not(*args)
        args = Conditions.arguments(instance_variable_get(:@scope).klass, args)
        super
      end
    end
  end
end
