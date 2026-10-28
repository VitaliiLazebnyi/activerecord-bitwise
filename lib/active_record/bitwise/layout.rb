# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # The flags of one column: their positions plus what is derived from them once (the mask of every
    # mapped bit and the flag names as Strings, which are compared instead of converting input to Symbols).
    class Layout
      extend T::Sig

      # The database column name, as it was declared.
      # @return [Symbol, String]
      sig { returns(Types::Name) }
      attr_reader :column_name

      # The mapping of symbol keys to bit position integers.
      # @return [Hash{Symbol => Integer}]
      sig { returns(Types::Positions) }
      attr_reader :mapping

      # The bitmask representing all known mapped positions.
      # @return [Integer]
      sig { returns(Integer) }
      attr_reader :known_mask

      # The list of mapping keys converted to strings for Symbol DoS prevention.
      # @return [Array<String>]
      sig { returns(T::Array[String]) }
      attr_reader :names

      # @param column_name [Symbol, String] The database column name.
      # @param mapping [Hash{Symbol => Integer}] Flag names to bit positions.
      sig { params(column_name: Types::Name, mapping: Types::Positions).void }
      def initialize(column_name, mapping)
        @column_name = column_name
        @mapping = mapping
        @known_mask = T.let(mapping.each_value.reduce(0) { |acc, elem| acc | (1 << elem) }, Integer)
        @names = T.let(mapping.keys.map(&:to_s).freeze, T::Array[String])
      end

      # Builds the frozen flag array for a list-like +value+, carrying over a raw marker.
      # @param value [Object] A flag name or a list of flag names.
      # @raise [ArgumentError] When the list exceeds {MAX_ARRAY_SIZE} elements.
      # @return [Array<Symbol, String>]
      sig { params(value: Object).returns(Types::Flags) }
      def flags(value)
        flags = items(value).map! { |item| symbolize(item) }
        flags.uniq!(&:to_s)
        RawMask.carry(flags, value).freeze
      end

      # The flags whose bits are set in +raw+, stamped with +raw+.
      # @param raw [Integer] A database bitmask.
      # @return [Array<Symbol, String>]
      sig { params(raw: Integer).returns(Types::Flags) }
      def decode(raw)
        RawMask.stamp(mapping.select { |_name, position| raw.anybits?(1 << position) }.keys, raw).freeze
      end

      # The bitmask of +value+: the unmapped bits its marker carries plus the bits of its mapped flags.
      # @param value [Object] A flag name or a list of flag names.
      # @return [Integer]
      sig { params(value: Object).returns(Integer) }
      def merge(value)
        (RawMask.mask_of(value) & ~known_mask) | mask(Array(value))
      end

      # The bitmask of the mapped flags among +values+; names that are not mapped contribute nothing.
      # @param values [Array<Object>] Flag names.
      # @return [Integer]
      sig { params(values: T::Array[Object]).returns(Integer) }
      def mask(values)
        values.reduce(0) { |acc, elem| acc | bit_for(elem) }
      end

      # Whether +item+ names a mapped flag.
      # @param item [Object] A flag name as users may spell it.
      # @return [Boolean]
      sig { params(item: Object).returns(T::Boolean) }
      def mapped?(item)
        names.include?(item.to_s)
      end

      # Whether +value+ is a bare numeric String that is not itself a flag name.
      # @param value [Object]
      # @return [Boolean]
      sig { params(value: Object).returns(T::Boolean) }
      def bitmask_string?(value)
        RawMask.digits?(value) && !names.include?(value)
      end

      private

      # The elements of +value+ without nil and empty strings.
      # @param value [Object] A flag name or a list of flag names.
      # @raise [ArgumentError] When there are more than {MAX_ARRAY_SIZE} of them.
      # @return [Array<Object>]
      sig { params(value: Object).returns(T::Array[Object]) }
      def items(value)
        list = Array(value).dup
        list.reject! { |item| item in nil | '' }
        # Array RAM Exhaustion Defense: Ceil at MAX_ARRAY_SIZE elements
        raise ArgumentError, "Array size cannot exceed #{MAX_ARRAY_SIZE}" if list.size > MAX_ARRAY_SIZE

        list
      end

      # Mapped names become Symbols; everything else stays a String.
      # @param item [Object]
      # @return [Symbol, String]
      sig { params(item: Object).returns(Types::Name) }
      def symbolize(item)
        name = item.to_s
        mapped?(name) ? name.to_sym : name
      end

      # The bit of +item+ when it names a mapped flag, otherwise 0.
      # @param item [Object]
      # @return [Integer]
      sig { params(item: Object).returns(Integer) }
      def bit_for(item)
        name = item.to_s
        mapped?(name) ? 1 << mapping.fetch(name.to_sym) : 0
      end
    end
  end
end
