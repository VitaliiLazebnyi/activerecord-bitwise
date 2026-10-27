# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/constants'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Normalization and validation of the user-supplied flag mapping and of the
      # method-name affixes.
      module Mapping
        extend T::Sig

        # Normalizes and validates a mapping into `{Symbol => Integer position}`.
        # @param column_name [T.any(Symbol, String)]
        # @param mapping [T.any(T::Hash[T.untyped, T.untyped], T::Array[T.untyped])]
        # @raise [ConfigurationError] On non-integer, negative, out-of-range, or duplicate positions.
        # @return [T::Hash[Symbol, Integer]]
        sig do
          params(column_name: Types::Name,
                 mapping: T.any(Types::Params, T::Array[T.untyped])).returns(Types::Positions)
        end
        def self.normalize(column_name, mapping)
          normalized = entries(column_name, mapping)
          if normalized.size != mapping.size
            raise ConfigurationError,
                  "Bitwise column #{column_name} mapping contains duplicate keys after symbolization"
          end

          reject_shared_positions!(column_name, normalized)
          normalized
        end

        # Computes the method name prefix string.
        # @param column_name [T.any(Symbol, String)]
        # @param affix [T.untyped] +true+ (singularized column name), a Symbol/String, or nothing.
        # @return [String] The prefix including its trailing underscore (empty for no prefix).
        sig { params(column_name: Types::Name, affix: T.untyped).returns(String) }
        def self.prefix(column_name, affix)
          base = affix_base(column_name, affix)
          base ? "#{base}_" : ''
        end

        # Computes the method name suffix string.
        # @param column_name [T.any(Symbol, String)]
        # @param affix [T.untyped] +true+ (singularized column name), a Symbol/String, or nothing.
        # @return [String] The suffix including its leading underscore (empty for no suffix).
        sig { params(column_name: Types::Name, affix: T.untyped).returns(String) }
        def self.suffix(column_name, affix)
          base = affix_base(column_name, affix)
          base ? "_#{base}" : ''
        end

        # The text an affix contributes to generated method names.
        # @param column_name [T.any(Symbol, String)]
        # @param affix [T.untyped]
        # @return [T.nilable(String)] Nil when no affix applies (an empty String is a real, empty affix).
        sig { params(column_name: Types::Name, affix: T.untyped).returns(T.nilable(String)) }
        def self.affix_base(column_name, affix)
          case affix
          when true then T.unsafe(column_name.to_s).singularize
          when Symbol, String then affix.to_s
          end
        end
        private_class_method :affix_base

        # Builds the `{Symbol => position}` pairs of a Hash or Array mapping.
        # @param column_name [T.any(Symbol, String)]
        # @param mapping [T.any(T::Hash[T.untyped, T.untyped], T::Array[T.untyped])]
        # @return [T::Hash[Symbol, Integer]]
        sig do
          params(column_name: Types::Name,
                 mapping: T.any(Types::Params, T::Array[T.untyped])).returns(Types::Positions)
        end
        def self.entries(column_name, mapping)
          if mapping.is_a?(Array)
            mapping.each_with_index.to_h { |key, index| [key.to_sym, index] }
          else
            mapping.to_h { |key, value| [key.to_sym, position(column_name, key, value)] }
          end
        end
        private_class_method :entries

        # Rejects mappings where several keys share one bit position.
        # @param column_name [T.any(Symbol, String)]
        # @param normalized [T::Hash[Symbol, Integer]]
        # @raise [ConfigurationError] When two keys share a position.
        # @return [void]
        sig { params(column_name: Types::Name, normalized: Types::Positions).void }
        def self.reject_shared_positions!(column_name, normalized)
          return if normalized.values.uniq.size == normalized.size

          raise ConfigurationError,
                "Bitwise column #{column_name} mapping assigns the same bit position to multiple keys: " \
                "#{normalized.inspect}. Values are bit POSITIONS (1 << position), not masks."
        end
        private_class_method :reject_shared_positions!

        # Validates a single mapping value as a bit position.
        # @param column_name [T.any(Symbol, String)]
        # @param key [T.untyped]
        # @param value [T.untyped]
        # @raise [ConfigurationError] When the value is not a usable bit position.
        # @return [Integer]
        sig { params(column_name: Types::Name, key: T.untyped, value: T.untyped).returns(Integer) }
        def self.position(column_name, key, value)
          digits = value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A\d+\z/))
          candidate = RawMask.integer(value) if digits
          return candidate if candidate&.between?(0, MAX_BIT_POSITION)

          raise ConfigurationError,
                "Bitwise column #{column_name} mapping key #{key} has invalid bit position #{value.inspect}. " \
                "Positions must be Integers between 0 and #{MAX_BIT_POSITION}; " \
                'they are bit POSITIONS (1 << position), not masks.'
        end
        private_class_method :position
      end
    end
  end
end
