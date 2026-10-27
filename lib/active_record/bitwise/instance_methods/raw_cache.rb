# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Per-record cache of the raw database bitmask of every bitwise column. It lets
      # saves write back unmapped ("forgotten") bits that the flag arrays cannot express.
      module RawCache
        extend T::Sig

        # Manually clears the cached raw bitmask values.
        # @return [void]
        sig { void }
        def clear_bitwise_raw_values_cache!
          T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, {})
        end

        # Reloads the record, invalidating the raw bitmask cache first.
        # @param args [T.untyped]
        # @return [T.untyped]
        sig { params(args: T.untyped).returns(T.untyped) }
        def reload(*args)
          clear_bitwise_raw_values_cache!
          super
        end

        # Returns (initializing when necessary) the per-record cache of raw database bitmasks.
        # @return [T::Hash[Symbol, Integer]]
        sig { returns(Types::Positions) }
        def _bitwise_raw_cache
          T.unsafe(self).instance_variable_get(:@_bitwise_raw_values) ||
            T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, {})
        end

        # Hydrates the raw cache for +column_name+ from the attribute's before-type-cast
        # value unless already present, and returns the cached raw integer.
        # @param column_name [Symbol]
        # @return [Integer]
        sig { params(column_name: Symbol).returns(Integer) }
        def _bitwise_hydrate_raw_cache(column_name)
          cache = _bitwise_raw_cache
          cache[column_name] ||= RawMask.extract(T.unsafe(self).read_attribute_before_type_cast(column_name))
          T.must(cache[column_name])
        end

        # Resets the raw bitmask cache after every save.
        # @return [void]
        sig { void }
        def _reset_bitwise_raw_value_caches
          clear_bitwise_raw_values_cache!
        end

        # Duplicated records intentionally drop the source record's unmapped
        # ("forgotten") bits: a dup is a new record and should only carry the flags
        # visible in Ruby, never invisible legacy bits.
        # @param other [T.untyped]
        # @return [T.untyped]
        sig { params(other: T.untyped).returns(T.untyped) }
        def initialize_dup(other)
          result = super
          clear_bitwise_raw_values_cache!
          T.unsafe(self).class.bitwise_definitions.each_key do |column_name|
            _bitwise_raw_cache[column_name] = 0
            _bitwise_copy_flags(column_name)
          end
          result
        end

        # Re-assigns the visible flags of +column_name+ so the duplicate owns a fresh array.
        # @param column_name [Symbol]
        # @return [void]
        sig { params(column_name: Symbol).void }
        def _bitwise_copy_flags(column_name)
          flags = T.unsafe(self).read_attribute(column_name)
          T.unsafe(self).write_attribute(column_name, flags.map { |flag| flag }) if flags.is_a?(Array)
        end
      end
    end
  end
end
