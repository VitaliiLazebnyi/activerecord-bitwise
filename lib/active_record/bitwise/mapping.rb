# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/errors'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Normalizes and validates the mapping a user declares for a bitwise column.
    module Mapping
      extend T::Sig

      # Normalizes and validates a mapping into `{Symbol => Integer position}`.
      # @param column_name [Symbol, String]
      # @param mapping [Object] A Hash of names to bit positions or an Array of names.
      # @raise [ArgumentError] When +mapping+ is neither a Hash nor an Array.
      # @raise [ConfigurationError] On non-integer, negative, out-of-range, or duplicate positions.
      # @return [Hash{Symbol => Integer}]
      sig { params(column_name: Types::Name, mapping: Object).returns(Types::Positions) }
      def self.normalize(column_name, mapping)
        pairs = entries(mapping)
        normalized = pairs.to_h { |key, value| [key.to_sym, position(column_name, key, value)] }
        unique_names!(column_name, pairs)
        unique_positions!(column_name, normalized)
      end

      # Validates a single mapping value as a bit position.
      # @param column_name [Symbol, String]
      # @param key [Object] The flag name.
      # @param value [Object] The declared position.
      # @raise [ConfigurationError] When the value is not a usable bit position.
      # @return [Integer]
      sig { params(column_name: Types::Name, key: Object, value: Object).returns(Integer) }
      def self.position(column_name, key, value)
        position = value.instance_of?(Integer) ? value : RawMask.decimal(value)
        return position if position&.between?(0, MAX_BIT_POSITION)

        raise ConfigurationError,
              "Bitwise column #{column_name} mapping key #{key} has invalid bit position #{value.inspect}. " \
              "Positions must be Integers between 0 and #{MAX_BIT_POSITION}; " \
              'they are bit POSITIONS (1 << position), not masks.'
      end

      # The declared (name, position) pairs; an Array declares positions by index.
      # @param mapping [Object] The declared mapping.
      # @raise [ArgumentError] When +mapping+ is neither a Hash nor an Array.
      # @return [Enumerable<Array<Object>>]
      sig { params(mapping: Object).returns(T::Enumerable[[Types::Name, Object]]) }
      def self.entries(mapping)
        case mapping
        in Array => names then names.each_with_index
        in Hash => positions then positions
        else raise ArgumentError, 'Mapping must be a Hash or an Array'
        end
      end
      private_class_method :entries

      # The highest bit position of +mapping+, or -1 when it is empty: the positions are distinct, so the bit
      # length of the mask they form is the highest position plus one.
      # @param mapping [Hash{Symbol => Integer}] A normalized mapping.
      # @return [Integer]
      sig { params(mapping: Types::Positions).returns(Integer) }
      def self.highest_position(mapping)
        mapping.each_value.sum { |position| 1 << position }.bit_length - 1
      end

      # Fails when two keys name the same flag once symbolized (:admin and "admin").
      # @param column_name [Symbol, String]
      # @param pairs [Enumerable<Array<Object>>] The declared (name, position) pairs.
      # @raise [ConfigurationError]
      # @return [void]
      sig { params(column_name: Types::Name, pairs: T::Enumerable[[Types::Name, Object]]).void }
      def self.unique_names!(column_name, pairs)
        # uniq! returns nil when it finds no duplicate to remove.
        return unless pairs.map { |key, _position| key.to_sym }.uniq!

        raise ConfigurationError, "Bitwise column #{column_name} mapping contains duplicate keys after symbolization"
      end
      private_class_method :unique_names!

      # Fails when two flags share a bit position.
      # @param column_name [Symbol, String]
      # @param normalized [Hash{Symbol => Integer}]
      # @raise [ConfigurationError] When two flags share a bit position.
      # @return [Hash{Symbol => Integer}] +normalized+.
      sig { params(column_name: Types::Name, normalized: Types::Positions).returns(Types::Positions) }
      def self.unique_positions!(column_name, normalized)
        return normalized if normalized.values.uniq.size == normalized.size

        raise ConfigurationError,
              "Bitwise column #{column_name} mapping assigns the same bit position to multiple keys: " \
              "#{normalized.inspect}. Values are bit POSITIONS (1 << position), not masks."
      end
      private_class_method :unique_positions!
    end
  end
end
