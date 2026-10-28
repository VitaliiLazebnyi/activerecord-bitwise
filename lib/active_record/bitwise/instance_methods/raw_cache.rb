# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/raw_mask'
require 'forwardable'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # The per-record cache of the raw database bitmasks, one per bitwise column. It lets saves
      # write back the unmapped ("forgotten") bits that the Ruby-visible flag arrays cannot express.
      module RawCache
        extend T::Sig
        extend T::Helpers
        extend Forwardable

        requires_ancestor { ActiveRecord::Base }

        # Name of the instance variable holding the cache.
        IVAR = :@_bitwise_raw_values
        private_constant :IVAR

        # Coerces an arbitrary raw marker into an Integer bitmask (0 when impossible).
        def_delegator 'ActiveRecord::Bitwise::RawMask', :lenient, :_bitwise_coerce_raw

        # Manually clears the cached raw bitmask values.
        # @return [void]
        sig { void }
        def clear_bitwise_raw_values_cache!
          instance_variable_set(IVAR, {})
        end

        # Resets the raw bitmask cache after every save.
        # @return [void]
        sig { void }
        def _reset_bitwise_raw_value_caches
          clear_bitwise_raw_values_cache!
        end

        # Reloads the record, invalidating the raw bitmask cache first.
        # @param args [Array<Object>] Passed on to ActiveRecord.
        # @return [ActiveRecord::Base]
        sig { params(args: Object).returns(ActiveRecord::Base) }
        def reload(*args)
          clear_bitwise_raw_values_cache!
          super
        end

        # Returns (initializing when necessary) the per-record cache of raw database bitmasks.
        # @return [Hash{Symbol => Integer}]
        sig { returns(T::Hash[Symbol, Integer]) }
        def _bitwise_raw_cache
          instance_variable_get(IVAR) || instance_variable_set(IVAR, {})
        end

        # Hydrates the raw cache for +column_name+ from the attribute's before-type-cast
        # value unless already present, and returns the cached raw integer.
        # @param column_name [Symbol]
        # @return [Integer]
        sig { params(column_name: Symbol).returns(Integer) }
        def _bitwise_hydrate_raw_cache(column_name)
          cache = _bitwise_raw_cache
          cache.fetch(column_name) { cache[column_name] = hydrated_raw(column_name) }
        end

        private

        # The value of the column getter: the flag array, stamped with the raw bitmask of the column.
        # @param column [Symbol] The column.
        # @param value [Object, nil] What the attribute reader returned.
        # @return [Object, nil]
        sig { params(column: Symbol, value: T.nilable(Object)).returns(T.nilable(Object)) }
        def _bitwise_read(column, value)
          raw = _bitwise_hydrate_raw_cache(column)
          flags = (value in nil) ? self.class.attribute_types.fetch(column.to_s).deserialize(nil) : value
          return flags unless flags.is_a?(Array) && !RawMask.stamped?(flags)

          RawMask.stamp(flags.dup, raw).freeze
        end

        # The raw bitmask of +column_name+ as the attribute held it before the type cast.
        # @param column_name [Symbol]
        # @return [Integer]
        sig { params(column_name: Symbol).returns(Integer) }
        def hydrated_raw(column_name)
          _bitwise_coerce_raw(RawMask.unwrap(read_attribute_before_type_cast(column_name)))
        end
      end
    end
  end
end
