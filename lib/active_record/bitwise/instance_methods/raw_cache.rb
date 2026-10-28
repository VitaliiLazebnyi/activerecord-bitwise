# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/instance_methods/model_access'
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
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }
        requires_ancestor { ModelAccess }

        # Manually clears the cached raw bitmask values.
        # @return [void]
        sig { void }
        def clear_bitwise_raw_values_cache!
          instance_variable_set(:@_bitwise_raw_values, {})
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
          instance_variable_get(:@_bitwise_raw_values) || instance_variable_set(:@_bitwise_raw_values, {})
        end

        # Hydrates the raw cache for +column_name+ from the attribute's before-type-cast
        # value unless already present, and returns the cached raw integer.
        # @param column_name [Symbol]
        # @return [Integer]
        sig { params(column_name: Symbol).returns(Integer) }
        def _bitwise_hydrate_raw_cache(column_name)
          cache = _bitwise_raw_cache
          unless cache.key?(column_name)
            raw_before = read_attribute_before_type_cast(column_name)
            marked = raw_before.is_a?(Array) && raw_before.instance_variable_defined?(:@_bitwise_raw_value)
            raw = marked ? raw_before.instance_variable_get(:@_bitwise_raw_value) : raw_before
            cache[column_name] = _bitwise_coerce_raw(raw)
          end
          T.unsafe(cache[column_name])
        end

        # Coerces an arbitrary raw marker into an Integer bitmask (0 when impossible).
        # @param value [T.untyped]
        # @return [Integer]
        sig { params(value: T.untyped).returns(Integer) }
        def _bitwise_coerce_raw(value)
          if value.is_a?(Integer)
            value
          elsif value.respond_to?(:to_i) # rubocop:disable Lint/NumberConversion -- capability check, as on main
            T.unsafe(value).to_i # rubocop:disable Lint/NumberConversion -- lenient coercion, as on main
          else
            0
          end
        end

        # Resets the raw bitmask cache after every save.
        # @return [void]
        sig { void }
        def _reset_bitwise_raw_value_caches
          instance_variable_set(:@_bitwise_raw_values, {})
        end
      end
    end
  end
end
