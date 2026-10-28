# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/definitions'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/type'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Rewrites the bitwise values of a conditions or assignments hash (`where`, `update_all`) into integer
    # bitmasks. Non-bitwise keys and values that already are integers pass through untouched.
    module Conditions
      extend T::Sig

      # A hash entry that holds flag names for a bitwise column.
      class Target
        extend T::Sig

        # The hash key, as the caller spelled it (the column name as a Symbol or as a String).
        # @return [Symbol, String]
        sig { returns(Types::Name) }
        attr_reader :key

        # The column the entry belongs to.
        # @return [Symbol]
        sig { returns(Symbol) }
        attr_reader :column

        # The flag names the caller supplied.
        # @return [Object]
        sig { returns(Object) }
        attr_reader :value

        # The bitwise type of the column.
        # @return [ActiveRecord::Bitwise::Type]
        sig { returns(Type) }
        attr_reader :type

        # @param key [Symbol, String] The hash key.
        # @param column [Symbol] The column the key names.
        # @param value [Object] The flag names.
        # @param type [ActiveRecord::Bitwise::Type] The bitwise type of the column.
        sig { params(key: Types::Name, column: Symbol, value: Object, type: Type).void }
        def initialize(key, column, value, type)
          @key = key
          @column = column
          @value = value
          @type = type
        end

        # The supplied flags, cast to the column's flag array.
        # @param refusal [String] Appended to the error message.
        # @raise [UnknownValueError] When a flag is missing from the mapping.
        # @return [Array<Symbol, String>]
        sig { params(refusal: String).returns(Types::Flags) }
        def flags(refusal)
          casted = type.cast(value) || []
          unknown = casted.reject { |flag| type.mapping_strings.include?(flag.to_s) }
          return casted if unknown.empty?

          raise UnknownValueError,
                "Unknown bitwise value(s) #{unknown.map(&:to_s).inspect} for column #{column}#{refusal}"
        end
      end

      # Finds the entries of a hash that hold flag names for a bitwise column.
      class Scan
        extend T::Sig

        # @param klass [Class] The model class owning the bitwise definitions.
        # @param hash [Hash] The conditions or assignments.
        # @param skip [Method] Tells which values are left alone (they already are masks, or SQL).
        sig { params(klass: Types::ModelClass, hash: Types::Params, skip: Method).void }
        def initialize(klass, hash, skip)
          @klass = klass
          @hash = hash
          @skip = skip
        end

        # The entries to rewrite, column by column (Symbol key first, then String key).
        # @return [Array<Target>]
        sig { returns(T::Array[Target]) }
        def targets
          @klass.bitwise_definitions.each_key.flat_map { |column| [[column, column], [column, column.to_s]] }
                .filter_map { |column, key| target(column, key) }
        end

        private

        # The entry for +key+, unless it is absent, left alone, or not a bitwise column.
        # @param column [Symbol] The bitwise column.
        # @param key [Symbol, String] A spelling of its name.
        # @return [Target, nil]
        sig { params(column: Symbol, key: Types::Name).returns(T.nilable(Target)) }
        def target(column, key)
          return unless @hash.key?(key)

          value = @hash[key]
          type = @klass.attribute_types[column.to_s]
          Target.new(key, column, value, type) if !@skip.call(value) && type.is_a?(Type)
        end
      end

      # Why an unknown value in an assignment is refused rather than ignored.
      REFUSAL = '; refusing to zero unrecognized flags via update_all'
      private_constant :REFUSAL

      # Serializes bitwise values inside a `where`-style conditions hash into their integer bitmask
      # representation (exact-match semantics). Non-bitwise keys and already-integer values pass
      # through untouched.
      # @param klass [Class] The model class owning the bitwise definitions.
      # @param hash [Hash] The conditions hash.
      # @raise [UnknownValueError] When a flag is missing from the mapping.
      # @return [Hash] The (possibly copied) conditions hash.
      sig { params(klass: Types::ModelClass, hash: Types::Params).returns(Types::Params) }
      def self.serialize(klass, hash)
        changes = Scan.new(klass, hash, method(:mask_like?)).targets.to_h do |target|
          [target.key, target.type.serialize(target.flags(''))]
        end
        changes.empty? ? hash : hash.merge(changes)
      end

      # The arguments of a `where`/`not` call with their leading conditions hash serialized.
      # @param klass [Class, nil] The model class of the relation (nil when there is none).
      # @param args [Array<Object>] The arguments of the call.
      # @raise [UnknownValueError] When a flag is missing from the mapping.
      # @return [Array<Object>] +args+, or a copy with the first argument replaced.
      sig { params(klass: T.nilable(Types::ModelClass), args: T::Array[Object]).returns(T::Array[Object]) }
      def self.arguments(klass, args)
        first = args.first
        return args unless first.is_a?(Hash) && klass && Definitions.bitwise?(klass)

        [serialize(klass, first), *args.drop(1)]
      end

      # Rewrites the bitwise values of an `update_all` assignments hash into SQL expressions that keep
      # the column's unmapped ("forgotten") bits: `(COALESCE(col, 0) & ~known_mask) | mask`. The mask
      # is recomputed from the flags alone (ignoring any smuggled raw-value marker), so `update_all`
      # cannot be used to inject arbitrary bits.
      # @param klass [Class] The model class owning the bitwise definitions.
      # @param updates [Hash] The assignments.
      # @raise [UnknownValueError] When a flag is missing from the mapping.
      # @return [Hash] A copy of +updates+ with the bitwise values rewritten.
      sig { params(klass: Types::ModelClass, updates: Types::Params).returns(Types::Params) }
      def self.assignments(klass, updates)
        updates.merge(Scan.new(klass, updates, method(:sql_or_mask?)).targets.to_h do |target|
          [target.key, assignment(klass, target)]
        end)
      end

      # The SQL expression that stores the flags of +target+ and keeps the unmapped bits.
      # @param klass [Class] The model class.
      # @param target [Target] The entry to rewrite.
      # @return [Arel::Nodes::SqlLiteral]
      sig { params(klass: Types::ModelClass, target: Target).returns(Arel::Nodes::SqlLiteral) }
      def self.assignment(klass, target)
        # serialize returns nil only for nil, and the flags are an Array.
        type = target.type
        mask = T.must(type.serialize(Array.new(target.flags(REFUSAL))))
        quoted = klass.connection.quote_column_name(target.column)
        Arel.sql("(COALESCE(#{quoted}, 0) & #{~type.known_mask}) | #{mask}")
      end
      private_class_method :assignment

      # Whether `where` leaves +value+ alone: it is nil, a mask, or a non-empty list of masks.
      # @param value [Object] A condition value.
      # @return [Boolean]
      sig { params(value: Object).returns(T::Boolean) }
      def self.mask_like?(value)
        case value
        in Integer | nil then true
        in Array => list then !list.empty? && list.all?(Integer)
        else false
        end
      end
      private_class_method :mask_like?

      # Whether `update_all` leaves +value+ alone: it is nil, a mask or SQL.
      # @param value [Object] An assigned value.
      # @return [Boolean]
      sig { params(value: Object).returns(T::Boolean) }
      def self.sql_or_mask?(value)
        value in Integer | nil | Arel::Nodes::SqlLiteral | Arel::Nodes::Node
      end
      private_class_method :sql_or_mask?
    end
  end
end
