# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/errors'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/type'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Rewrites hash conditions and batch-update assignments so that flag arrays are
    # replaced by their integer bitmask representation.
    module Conditions
      extend T::Sig

      # Serializes bitwise values inside a `where`-style conditions hash into their
      # integer bitmask representation (exact-match semantics). Non-bitwise keys and
      # already-integer values pass through untouched.
      # @param klass [T.untyped] The model class owning the bitwise definitions.
      # @param hash [T::Hash[T.untyped, T.untyped]] The conditions hash.
      # @raise [UnknownValueError] If a flag array contains values missing from the mapping.
      # @return [T::Hash[T.untyped, T.untyped]] The (possibly copied) conditions hash.
      sig { params(klass: T.untyped, hash: Types::Params).returns(Types::Params) }
      def self.serialize(klass, hash)
        masks = bitwise_entries(klass, hash).filter_map do |column_name, key, typecaster|
          value = hash.fetch(key)
          [key, typecaster.serialize(known_flags(typecaster, value, column_name, ''))] unless passthrough?(value)
        end
        masks.empty? ? hash : hash.merge(masks.to_h)
      end

      # Rewrites the flag arrays of an `update_all` assignment hash into
      # ghost-bit-preserving SQL expressions:
      # `(COALESCE(col, 0) & ~known_mask) | mask`. Unmapped ("forgotten") bits of every
      # matched row are preserved, matching the behavior of instance-level saves.
      # @param klass [T.untyped] The model class owning the bitwise definitions.
      # @param updates [T::Hash[T.untyped, T.untyped]] The assignments.
      # @raise [UnknownValueError] If a flag array contains values missing from the mapping.
      # @return [T::Hash[T.untyped, T.untyped]] A copy of +updates+ with flag arrays replaced.
      sig { params(klass: T.untyped, updates: Types::Params).returns(Types::Params) }
      def self.assignments(klass, updates)
        expressions = bitwise_entries(klass, updates).filter_map do |column_name, key, typecaster|
          value = updates.fetch(key)
          [key, update_expression(klass, column_name, typecaster, value)] unless verbatim?(value)
        end
        updates.merge(expressions.to_h)
      end

      # Every present hash key that addresses a bitwise column.
      # @param klass [T.untyped] The model class.
      # @param hash [T::Hash[T.untyped, T.untyped]] The conditions or assignments.
      # @return [T::Array[[Symbol, T.untyped, Type]]] Column name, hash key and type of each match.
      sig do
        params(klass: T.untyped, hash: Types::Params).returns(T::Array[[Symbol, T.untyped, Type]])
      end
      def self.bitwise_entries(klass, hash)
        klass.bitwise_definitions.each_key.flat_map { |column_name| column_entries(klass, hash, column_name) }
      end
      private_class_method :bitwise_entries

      # The hash keys (Symbol and String spelling) addressing one bitwise column.
      # @param klass [T.untyped] The model class.
      # @param hash [Types::Params] The conditions or assignments.
      # @param column_name [Symbol]
      # @return [T::Array[[Symbol, T.untyped, Type]]]
      sig { params(klass: T.untyped, hash: Types::Params, column_name: Symbol).returns(T::Array[[Symbol, T.untyped, Type]]) }
      def self.column_entries(klass, hash, column_name)
        typecaster = klass.attribute_types[column_name.to_s]
        keys = [column_name, column_name.to_s].select { |key| hash.key?(key) }
        (typecaster in Type) ? keys.map { |key| [column_name, key, typecaster] } : []
      end
      private_class_method :column_entries

      # Assignment values written as-is: Integers, NULL and ready-made Arel SQL.
      # @param value [T.untyped]
      # @return [Boolean]
      sig { params(value: T.untyped).returns(T::Boolean) }
      def self.verbatim?(value)
        RawMask.integer?(value) || value.nil? || (value in Arel::Nodes::Node) || (value in Arel::Nodes::SqlLiteral)
      end
      private_class_method :verbatim?

      # Condition values that are compared as-is: Integers, NULL and integer arrays.
      # @param value [T.untyped]
      # @return [Boolean]
      sig { params(value: T.untyped).returns(T::Boolean) }
      def self.passthrough?(value)
        RawMask.integer?(value) || value.nil? || ((value in Array) && !value.empty? && value.all?(Integer))
      end
      private_class_method :passthrough?

      # Casts +value+ and verifies every flag is mapped.
      # @param typecaster [Type]
      # @param value [T.untyped]
      # @param column_name [Symbol]
      # @param advice [String] Text appended to the error message.
      # @raise [UnknownValueError] If a flag is missing from the mapping.
      # @return [T::Array[T.any(Symbol, String)]] The casted flags.
      sig do
        params(typecaster: Type, value: T.untyped, column_name: Symbol, advice: String)
          .returns(Types::Flags)
      end
      def self.known_flags(typecaster, value, column_name, advice)
        casted = T.must(typecaster.cast(value))
        unknown = casted.reject { |flag| typecaster.mapping_strings.include?(flag.to_s) }
        return casted if unknown.empty?

        raise UnknownValueError,
              "Unknown bitwise value(s) #{unknown.map(&:to_s)} for column #{column_name}#{advice}"
      end
      private_class_method :known_flags

      # The SQL expression assigning +value+ while preserving unmapped bits.
      # @param klass [T.untyped]
      # @param column_name [Symbol]
      # @param typecaster [Type]
      # @param value [T.untyped]
      # @return [T.untyped] An Arel SQL literal.
      sig { params(klass: T.untyped, column_name: Symbol, typecaster: Type, value: T.untyped).returns(T.untyped) }
      def self.update_expression(klass, column_name, typecaster, value)
        advice = '; refusing to zero unrecognized flags via update_all'
        casted = known_flags(typecaster, value, column_name, advice)
        # Recompute the mask from the flags alone (ignoring any smuggled raw-value
        # marker) so update_all cannot be used to inject arbitrary bits.
        mask = typecaster.serialize([*casted])
        quoted_column = klass.connection.quote_column_name(column_name)
        Arel.sql("(COALESCE(#{quoted_column}, 0) & #{~typecaster.known_mask}) | #{mask}")
      end
      private_class_method :update_expression
    end
  end
end
