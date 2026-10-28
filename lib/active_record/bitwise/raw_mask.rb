# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Helpers for the "raw bitmask" marker that flag arrays carry. The marker holds
    # the complete database integer, including unmapped ("forgotten") bits that the
    # Ruby-visible flag array cannot express, so saves can write them back unchanged.
    module RawMask
      extend T::Sig

      # Name of the instance variable carrying the marker on a flag array.
      IVAR = :@_bitwise_raw_value
      private_constant :IVAR

      # Whether +value+ is an Integer (Integer has no subclasses, so this is an exact check).
      # @param value [T.untyped] Any object.
      # @return [Boolean]
      sig { params(value: T.untyped).returns(T::Boolean) }
      def self.integer?(value)
        case value
        when Integer then true
        else false
        end
      end

      # Whether +value+ is an Array carrying a raw-bitmask marker.
      # @param value [T.untyped] Any object.
      # @return [Boolean]
      sig { params(value: T.untyped).returns(T::Boolean) }
      def self.stamped?(value)
        return false unless value.is_a?(Array)

        value.instance_variable_defined?(IVAR)
      end

      # Reads the marker of a stamped array.
      # @param array [T::Array[T.untyped]] An array for which {.stamped?} is true.
      # @return [T.untyped] The marker (normally an Integer).
      sig { params(array: T::Array[T.untyped]).returns(T.untyped) }
      def self.read(array)
        array.instance_variable_get(IVAR)
      end

      # Writes +raw+ as the marker of +array+ and returns the array.
      # @param array [T::Array[T.untyped]] The array to stamp (must not be frozen).
      # @param raw [T.untyped] The marker value.
      # @return [T::Array[T.untyped]] +array+.
      sig { params(array: T::Array[T.untyped], raw: T.untyped).returns(T::Array[T.untyped]) }
      def self.stamp(array, raw)
        array.instance_variable_set(IVAR, raw)
        array
      end

      # Lenient integer conversion (`"12abc"` becomes 12, `nil` becomes 0). Raw database
      # values may legitimately arrive as strings or other numerics (e.g. SQLite), and
      # garbage must degrade to a bitmask rather than raise.
      # @param value [T.untyped] Anything responding to +to_i+.
      # @return [Integer]
      sig { params(value: T.untyped).returns(Integer) }
      def self.integer(value)
        value.to_i # rubocop:disable Lint/NumberConversion -- lenient coercion is the documented contract
      end

      # Coerces an arbitrary marker into an Integer bitmask (0 when impossible).
      # @param value [T.untyped] Any object.
      # @return [Integer]
      sig { params(value: T.untyped).returns(Integer) }
      def self.coerce(value)
        return value if integer?(value)

        value.respond_to?(:to_i) ? integer(value) : 0 # rubocop:disable Lint/NumberConversion -- capability check, not a conversion
      end

      # The shared, frozen, empty flag array (raw mask 0).
      # @return [T::Array[T.untyped]]
      sig { returns(T::Array[T.untyped]) }
      def self.empty
        stamp([], 0).freeze
      end

      # The flag names of +mapping+ as frozen Strings (compared instead of converting input to Symbols).
      # @param mapping [T::Hash[Symbol, Integer]]
      # @return [T::Array[String]]
      sig { params(mapping: Types::Positions).returns(T::Array[String]) }
      def self.names(mapping)
        mapping.keys.map(&:to_s).freeze
      end

      # The bitmask covering every bit position of +mapping+.
      # @param mapping [T::Hash[Symbol, Integer]] Flag names to bit positions.
      # @return [Integer]
      sig { params(mapping: Types::Positions).returns(Integer) }
      def self.known_mask(mapping)
        mapping.each_value.reduce(0) { |acc, elem| acc | (1 << elem) }
      end

      # The marker of +value+ when it is a stamped array, otherwise 0.
      # @param value [T.untyped] Any object.
      # @return [Integer]
      sig { params(value: T.untyped).returns(Integer) }
      def self.mask_of(value)
        stamped?(value) ? coerce(read(value)) : 0
      end

      # The marker of +value+ when it is a stamped array, otherwise +value+ itself,
      # coerced to an Integer bitmask.
      # @param value [T.untyped] Any object.
      # @return [Integer]
      sig { params(value: T.untyped).returns(Integer) }
      def self.extract(value)
        stamped?(value) ? coerce(read(value)) : coerce(value)
      end
    end
  end
end
