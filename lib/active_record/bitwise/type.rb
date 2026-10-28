# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/recursion_guard'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # ActiveModel attribute type translating between an Array of flag names and the
    # integer bitmask stored in the database.
    class Type < ActiveRecord::Type::Value
      extend T::Sig

      # The column name associated with this type.
      # @return [Symbol]
      sig { returns(Symbol) }
      attr_reader :column_name

      # The default array of values (applied to new records via the attribute API).
      # @return [Array<Symbol, String>]
      sig { returns(Types::Flags) }
      attr_reader :default

      # Initializes the bitwise type cast configuration.
      # @param column_name [Symbol, String] The column name.
      # @param mapping [Hash{Symbol => Integer}] The mapping of keys to bit positions.
      # @param default [Array<Symbol, String>, nil] The default values.
      # @return [void]
      sig { params(column_name: Types::Name, mapping: Types::Positions, default: T.nilable(Types::Flags)).void }
      def initialize(column_name, mapping, default)
        @column_name = T.let(column_name.to_sym, Symbol)
        @default = T.let(Array(default), Types::Flags)
        @layout = T.let(Layout.new(@column_name, mapping), Layout)
        @empty = T.let(RawMask.empty, Types::Flags)
        super()
      end

      # The mapping of symbol keys to bit position integers.
      # @return [Hash{Symbol => Integer}]
      sig { returns(Types::Positions) }
      def mapping
        @layout.mapping
      end

      # The bitmask representing all known mapped positions.
      # @return [Integer]
      sig { returns(Integer) }
      def known_mask
        @layout.known_mask
      end

      # The list of mapping keys converted to strings for Symbol DoS prevention.
      # @return [Array<String>]
      sig { returns(T::Array[String]) }
      def mapping_strings
        @layout.names
      end

      # Casts a value to a frozen array of symbols or strings.
      # @param value [Object, nil] The value to cast.
      # @raise [ArgumentError] When the value cannot be meaningfully cast (Hash, true, false)
      #   or exceeds {MAX_ARRAY_SIZE} elements.
      # @return [Array<Symbol, String>, nil] The casted array or nil.
      sig { override.params(value: T.nilable(Object)).returns(T.nilable(Types::Flags)) }
      def cast(value)
        case value
        in nil then nil
        in Integer then deserialize(value)
        else flags(value)
        end
      end

      # Casts a value that is neither nil nor an Integer the way {#cast} does.
      # @param value [Object] The value to cast.
      # @raise [ArgumentError] When the value cannot be meaningfully cast (Hash, true, false)
      #   or exceeds {MAX_ARRAY_SIZE} elements.
      # @return [Array<Symbol, String>]
      sig { params(value: Object).returns(Types::Flags) }
      def flags(value)
        case value
        in Array => flags if flags.frozen? && RawMask.stamped?(flags) then flags
        else cast_unstamped(value)
        end
      end

      # The bitmask of the mapped flags in +flags+. Unlike {#serialize}, the unmapped bits a flag array
      # carries are left out.
      # @param flags [Array<Object>] Flag names.
      # @return [Integer]
      sig { params(flags: T::Array[Object]).returns(Integer) }
      def mask(flags)
        @layout.mask(flags)
      end

      # Deserializes a database integer value into an array of symbols or strings.
      # A database NULL deserializes to an empty array; the configured default is
      # applied only to new records (via the attribute API), never resurrected for
      # persisted NULL rows, so getters, scopes, and persistence stay consistent.
      # @param value [Object, nil] The raw value from the database.
      # @return [Array<Symbol, String>] The array of symbols/strings represented by the bitmask.
      sig { override.params(value: T.nilable(Object)).returns(Types::Flags) }
      def deserialize(value)
        RecursionGuard.run { decode(value) }
      end

      # Serializes an array of symbols into a database integer bitmask, merging
      # any unmapped ("forgotten") bits carried on the array's raw-value marker.
      # @param value [Object, nil] The value to serialize.
      # @raise [ActiveModel::RangeError] When the bitmask does not fit a signed 64-bit column.
      # @return [Integer, nil] The resulting integer bitmask.
      sig { override.params(value: T.nilable(Object)).returns(T.nilable(Integer)) }
      def serialize(value)
        case value
        in nil then nil
        in Integer => bitmask then checked(bitmask)
        else checked(@layout.merge(value))
        end
      end

      private

      # Casts a value that is not nil, an Integer or an already stamped, frozen flag array.
      # @param value [Object] The value to cast.
      # @raise [ArgumentError] For a Hash, +true+ or +false+.
      # @return [Array<Symbol, String>]
      sig { params(value: Object).returns(Types::Flags) }
      def cast_unstamped(value)
        case value
        in Hash | true | false
          raise ArgumentError, "cannot cast #{value} to a bitwise flag array for column #{column_name}"
        # A bare numeric string (e.g. from a raw SQLite read) is a bitmask, not a flag name.
        in String => text if @layout.bitmask_string?(text) then deserialize(Integer(text, 10))
        else @layout.flags(value)
        end
      end

      # Decodes +value+ the way {#deserialize} does, without the recursion guard.
      # @param value [Object, nil] The raw value from the database.
      # @return [Array<Symbol, String>]
      sig { params(value: T.nilable(Object)).returns(Types::Flags) }
      def decode(value)
        case value
        in nil then @empty
        in Array => list then decode_array(list)
        else @layout.decode(RawMask.integer(value))
        end
      end

      # Re-wraps an Array input as a frozen flag array stamped with its raw mask.
      # @param value [Array<Object>] The array to decode.
      # @raise [Error] When the array cannot be cast.
      # @return [Array<Symbol, String>]
      sig { params(value: T::Array[Object]).returns(Types::Flags) }
      def decode_array(value)
        raw = RawMask.stamped?(value) ? RawMask.read(value) : serialize(value)
        array = cast(value) or raise Error, 'Casting failed'
        RawMask.stamp(array.dup, raw).freeze
      end

      # Returns +bitmask+ unless it is out of range for a signed 64-bit column (the widest one). SQLite
      # would otherwise store it as a lossy REAL, and the other adapters fail late with their own errors.
      # @param bitmask [Integer]
      # @raise [ActiveModel::RangeError] When +bitmask+ needs more than 64 bits.
      # @return [Integer] +bitmask+.
      sig { params(bitmask: Integer).returns(Integer) }
      def checked(bitmask)
        return bitmask if bitmask.bit_length < 64

        raise ActiveModel::RangeError,
              "#{bitmask} is out of range for column #{column_name}: it must fit a signed 64-bit integer"
      end
    end
  end
end
