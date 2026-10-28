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

      # The part of a String that +String#to_i+ reads: optional blanks and sign, then digits (single
      # underscores allowed between digits).
      LEADING_INTEGER = /\A\s*[+-]?\d+(?:_\d+)*/
      private_constant :LEADING_INTEGER

      # Name of the instance variable carrying the marker on a flag array.
      IVAR = :@_bitwise_raw_value
      private_constant :IVAR

      # Whether +value+ is an Array carrying a raw-bitmask marker.
      # @param value [Object] Any object.
      # @return [Boolean]
      sig { params(value: Object).returns(T::Boolean) }
      def self.stamped?(value)
        value.instance_variable_defined?(IVAR)
      end

      # Reads the marker of a stamped array.
      # @param value [Object] Any object; unstamped objects have no marker.
      # @return [Object, nil] The marker (normally an Integer), or nil when there is none.
      sig { params(value: Object).returns(T.nilable(Object)) }
      def self.read(value)
        value.instance_variable_get(IVAR)
      end

      # Writes +raw+ as the marker of +array+ and returns the array.
      # @param array [Array] The array to stamp (must not be frozen).
      # @param raw [Object, nil] The marker value.
      # @return [Array] +array+.
      sig { type_parameters(:Item).params(array: T::Array[T.type_parameter(:Item)], raw: T.nilable(Object)).returns(T::Array[T.type_parameter(:Item)]) }
      def self.stamp(array, raw)
        array.instance_variable_set(IVAR, raw)
        array
      end

      # The marker of +value+ when it is a stamped array, otherwise +value+ itself.
      # @param value [Object, nil] Any object.
      # @return [Object, nil]
      sig { params(value: T.nilable(Object)).returns(T.nilable(Object)) }
      def self.unwrap(value)
        value.is_a?(Array) && stamped?(value) ? read(value) : value
      end

      # Copies the marker of +source+ (when it is a stamped array with a truthy marker) onto +target+.
      # @param target [Array] The array to stamp (must not be frozen).
      # @param source [Object] Any object.
      # @return [Array] +target+.
      sig { type_parameters(:Item).params(target: T::Array[T.type_parameter(:Item)], source: Object).returns(T::Array[T.type_parameter(:Item)]) }
      def self.carry(target, source)
        marker = read(source) if source.is_a?(Array) && stamped?(source)
        marker ? stamp(target, marker) : target
      end

      # The shared, frozen, empty flag array (raw mask 0).
      # @return [Array]
      sig { returns(Types::Flags) }
      def self.empty
        stamp([], 0).freeze
      end

      # Whether +value+ is a String of decimal digits only.
      # @param value [Object] Any object.
      # @return [Boolean]
      sig { params(value: Object).returns(T::Boolean) }
      def self.digits?(value)
        value.is_a?(String) && value.match?(/\A\d+\z/)
      end

      # Integer value of +value+: a String contributes its leading digits like +String#to_i+ does ("12abc" is
      # 12); anything else is converted by +Integer()+, which accepts numbers and any object that defines
      # +to_i+ or +to_int+.
      # @param value [Object] An Integer, a String, another number or an object that responds to +to_i+.
      #   (Declared +T.untyped+: Sorbet types +Integer()+ for numbers and Strings only, but the conversion
      #   is duck-typed.)
      # @raise [TypeError] When +value+ cannot be converted.
      # @return [Integer]
      sig { params(value: T.untyped).returns(Integer) }
      def self.integer(value)
        value.is_a?(String) ? Integer(value[LEADING_INTEGER] || '0', 10) : Integer(value)
      end

      # Like {integer}, but anything that cannot be converted (including nil) is 0.
      # @param value [Object, nil] Any object. (Declared +T.untyped+ for the same reason as in {integer}.)
      # @return [Integer]
      sig { params(value: T.untyped).returns(Integer) }
      def self.lenient(value)
        integer(value)
      rescue ArgumentError, TypeError, ::RangeError
        0
      end

      # The raw bitmask of +value+: its marker when it is a stamped array, otherwise 0.
      # @param value [Object] Any object.
      # @return [Integer]
      sig { params(value: Object).returns(Integer) }
      def self.mask_of(value)
        lenient(value.is_a?(Array) && stamped?(value) ? read(value) : 0)
      end
    end
  end
end
