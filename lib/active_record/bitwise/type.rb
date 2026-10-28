# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/constants'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/recursion_guard'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # ActiveModel attribute type translating between an Array of flag names and the
    # integer bitmask stored in the database.
    class Type < ActiveRecord::Type::Value # rubocop:disable Metrics/ClassLength -- cohesive type handler (main disabled it too)
      extend T::Sig

      # The column name associated with this type.
      # @return [Symbol]
      sig { returns(Symbol) }
      attr_reader :column_name

      # The mapping of symbol keys to bit position integers.
      # @return [T::Hash[Symbol, Integer]]
      sig { returns(Types::Positions) }
      attr_reader :mapping

      # The default array of values (applied to new records via the attribute API).
      # @return [T::Array[T.any(Symbol, String)]]
      sig { returns(Types::Flags) }
      attr_reader :default

      # The bitmask representing all known mapped positions.
      # @return [Integer]
      sig { returns(Integer) }
      attr_reader :known_mask

      # The list of mapping keys converted to strings for Symbol DoS prevention.
      # @return [T::Array[String]]
      sig { returns(T::Array[String]) }
      attr_reader :mapping_strings

      # Initializes the bitwise type cast configuration.
      # @param column_name [T.any(Symbol, String)] The column name.
      # @param mapping [T::Hash[Symbol, Integer]] The mapping of keys to bit positions.
      # @param default [T.nilable(T::Array[T.any(Symbol, String)])] The default values.
      # @return [void]
      sig do
        params(column_name: Types::Name, mapping: Types::Positions,
               default: T.nilable(Types::Flags)).void
      end
      def initialize(column_name, mapping, default)
        @column_name = T.let(column_name.to_sym, Symbol)
        @mapping = mapping
        @default = T.let(default || [], Types::Flags)
        @known_mask = T.let(RawMask.known_mask(mapping), Integer)
        @mapping_strings = T.let(RawMask.names(mapping), T::Array[String])
        @empty_value = T.let(RawMask.empty, Types::Flags)
        super()
      end

      # Casts a value to a frozen array of symbols or strings.
      # @param value [T.untyped] The value to cast.
      # @raise [ArgumentError] When the value cannot be meaningfully cast (Hash, true, false)
      #   or exceeds {MAX_ARRAY_SIZE} elements.
      # @return [T.nilable(T::Array[T.any(Symbol, String)])] The casted array or nil.
      sig { override.params(value: T.untyped).returns(T.nilable(Types::Flags)) }
      def cast(value)
        return nil if value.nil?
        return deserialize(value) if value.is_a?(Integer)
        return value if value.is_a?(Array) && value.frozen? && value.instance_variable_defined?(:@_bitwise_raw_value)

        assert_castable(value)
        # A bare numeric string (e.g. from a raw SQLite read) is a bitmask, not a flag name.
        return deserialize(value.to_i) if bitmask_string?(value) # rubocop:disable Lint/NumberConversion -- bitmask_string? guarantees digits only

        build_flags(value)
      end

      # Deserializes a database integer value into an array of symbols or strings.
      # A database NULL deserializes to an empty array; the configured default is
      # applied only to new records (via the attribute API), never resurrected for
      # persisted NULL rows, so getters, scopes, and persistence stay consistent.
      # @param value [T.untyped] The raw value from the database.
      # @return [T::Array[T.any(Symbol, String)]] The array of symbols/strings represented by the bitmask.
      sig { override.params(value: T.untyped).returns(Types::Flags) }
      def deserialize(value)
        RecursionGuard.run do
          next @empty_value if value.nil?

          value.is_a?(Array) ? decode_array(value) : decode_mask(value.to_i) # rubocop:disable Lint/NumberConversion -- lenient coercion, as before the refactoring
        end
      end

      # Serializes an array of symbols into a database integer bitmask, merging
      # any unmapped ("forgotten") bits carried on the array's raw-value marker.
      # @param value [T.untyped] The value to serialize.
      # @return [T.nilable(Integer)] The resulting integer bitmask.
      sig { override.params(value: T.untyped).returns(T.nilable(Integer)) }
      def serialize(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)

        (marker_mask(value) & ~@known_mask) | mask_for(Array(value))
      end

      private

      # Rejects values that cannot be meaningfully cast to a flag array.
      # @param value [T.untyped]
      # @raise [ArgumentError] For a Hash, +true+ or +false+.
      # @return [void]
      sig { params(value: T.untyped).void }
      def assert_castable(value)
        return unless value.is_a?(Hash) || value == true || value == false

        raise ArgumentError, "cannot cast #{value.inspect} to a bitwise flag array for column #{column_name}"
      end

      # Whether +value+ is a bare numeric String that is not itself a flag name.
      # @param value [T.untyped]
      # @return [T.nilable(Boolean)]
      sig { params(value: T.untyped).returns(T.nilable(T::Boolean)) }
      def bitmask_string?(value)
        value.is_a?(String) && !@mapping_strings.include?(value) && value.match?(/\A\d+\z/)
      end

      # Builds the frozen flag array for a list-like +value+, carrying over a raw marker.
      # @param value [T.untyped]
      # @raise [ArgumentError] When the list exceeds {MAX_ARRAY_SIZE} elements.
      # @return [T::Array[T.any(Symbol, String)]]
      sig { params(value: T.untyped).returns(Types::Flags) }
      def build_flags(value)
        # Strip empty strings and nil
        arr = Array(value).dup
        arr.reject! { |item| item.nil? || item == '' }

        # Array RAM Exhaustion Defense: Ceil at MAX_ARRAY_SIZE elements
        raise ArgumentError, "Array size cannot exceed #{MAX_ARRAY_SIZE}" if arr.size > MAX_ARRAY_SIZE

        processed = arr.map! { |item| symbolize(item) }
        processed.uniq!(&:to_s)
        carry_marker(processed, value)
        processed.freeze
      end

      # Preserves the raw bitmask marker of +source+ (when it has a truthy one) on +target+.
      # @param target [T::Array[T.untyped]]
      # @param source [T.untyped]
      # @return [void]
      sig { params(target: T::Array[T.untyped], source: T.untyped).void }
      def carry_marker(target, source)
        raw = (source.instance_variable_get(:@_bitwise_raw_value) if source.is_a?(Array) && stamped_array?(source))
        target.instance_variable_set(:@_bitwise_raw_value, raw) if raw
      end

      # Whether +value+ carries a raw-bitmask marker.
      # @param value [T::Array[T.untyped]]
      # @return [Boolean]
      sig { params(value: T::Array[T.untyped]).returns(T::Boolean) }
      def stamped_array?(value)
        value.instance_variable_defined?(:@_bitwise_raw_value)
      end

      # Mapped names become Symbols; everything else stays a String.
      # @param item [T.untyped]
      # @return [T.any(Symbol, String)]
      sig { params(item: T.untyped).returns(Types::Name) }
      def symbolize(item)
        val_str = item.to_s
        @mapping_strings.include?(val_str) ? val_str.to_sym : val_str
      end

      # Re-wraps an Array input as a frozen flag array stamped with its raw mask.
      # @param value [T::Array[T.untyped]]
      # @raise [Error] When the array cannot be cast.
      # @return [T::Array[T.any(Symbol, String)]]
      sig { params(value: T::Array[T.untyped]).returns(Types::Flags) }
      def decode_array(value)
        raw = stamped_array?(value) ? value.instance_variable_get(:@_bitwise_raw_value) : serialize(value)
        array = cast(value)
        raise Error, 'Casting failed' if array.nil?

        array_dup = array.dup
        array_dup.instance_variable_set(:@_bitwise_raw_value, raw)
        array_dup.freeze
      end

      # The flags whose bits are set in +raw_value+, stamped with +raw_value+.
      # @param raw_value [Integer]
      # @return [T::Array[T.any(Symbol, String)]]
      sig { params(raw_value: Integer).returns(Types::Flags) }
      def decode_mask(raw_value)
        array = []
        @mapping.each do |sym, bit_position|
          array << sym if raw_value.anybits?(1 << bit_position)
        end

        array.instance_variable_set(:@_bitwise_raw_value, raw_value)
        array.freeze
      end

      # The unmapped bits carried by the raw-value marker of +value+ (0 when there is none).
      # @param value [T.untyped]
      # @return [Integer]
      sig { params(value: T.untyped).returns(Integer) }
      def marker_mask(value)
        marker = value.is_a?(Array) && stamped_array?(value) ? value.instance_variable_get(:@_bitwise_raw_value) : 0
        if marker.is_a?(Integer)
          marker
        elsif marker.respond_to?(:to_i) # rubocop:disable Lint/NumberConversion -- capability check, not a conversion
          marker.to_i # rubocop:disable Lint/NumberConversion -- lenient coercion, as before the refactoring
        else
          0
        end
      end

      # ORs the bit of every mapped flag in +values+.
      # @param values [T::Array[T.untyped]]
      # @return [Integer]
      sig { params(values: T::Array[T.untyped]).returns(Integer) }
      def mask_for(values)
        new_mask = 0
        values.each do |val|
          val_str = val.to_s
          new_mask |= (1 << T.unsafe(@mapping[val_str.to_sym])) if @mapping_strings.include?(val_str)
        end
        new_mask
      end
    end
  end
end
