# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/instance_methods/model_access'
require 'active_record/bitwise/instance_methods/raw_cache'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/type'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Intercepts every attribute write path so bitwise arrays are always stamped
      # with the current raw bitmask, preserving "forgotten bits" on save.
      module AttributeWrites
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }
        requires_ancestor { ModelAccess }
        requires_ancestor { RawCache }

        # Intercepts every attribute write (generated setters, `write_attribute`,
        # `self[:col] = ...`) so bitwise arrays are always stamped with the current
        # raw bitmask. This preserves "forgotten bits" even for write paths that
        # bypass the generated setter.
        # @note Both `_write_attribute` (used by generated writers) and
        #   `write_attribute` (used by `[]=` and direct calls) must be overridden:
        #   modern ActiveRecord writes to the attribute set directly from both.
        # @param attr_name [T.untyped]
        # @param value [T.untyped]
        # @return [T.untyped]
        sig { params(attr_name: T.untyped, value: T.untyped).returns(T.untyped) }
        def _write_attribute(attr_name, value)
          super(attr_name, _bitwise_intercept_write(attr_name, value))
        end

        # (see #_write_attribute)
        # @param attr_name [T.untyped]
        # @param value [T.untyped]
        # @return [T.untyped]
        sig { params(attr_name: T.untyped, value: T.untyped).returns(T.untyped) }
        def write_attribute(attr_name, value)
          super(attr_name, _bitwise_intercept_write(attr_name, value))
        end

        # Prepares +value+ for storage when +attr_name+ is a bitwise column;
        # returns it untouched otherwise.
        # @param attr_name [T.untyped]
        # @param value [T.untyped]
        # @return [T.untyped]
        sig { params(attr_name: T.untyped, value: T.untyped).returns(T.untyped) }
        def _bitwise_intercept_write(attr_name, value)
          column_name = attr_name.to_sym
          typecaster = _bitwise_typecaster(column_name)
          typecaster ? _bitwise_prepare_value(column_name, typecaster, value) : value
        end

        # The bitwise type of +column_name+, or nil for ordinary columns.
        # @param column_name [Symbol]
        # @return [T.nilable(ActiveRecord::Bitwise::Type)]
        sig { params(column_name: Symbol).returns(T.nilable(ActiveRecord::Bitwise::Type)) }
        def _bitwise_typecaster(column_name)
          return nil unless _bitwise_model.bitwise_definitions.key?(column_name)

          typecaster = _bitwise_model.attribute_types[column_name.to_s]
          typecaster if typecaster in ActiveRecord::Bitwise::Type
        end

        # Casts +value+ and synchronizes the raw bitmask cache:
        # * arrays carrying a raw marker (e.g. cast from an Integer) update the cache;
        # * plain arrays are stamped with the currently cached raw bitmask;
        # * nil clears the cached raw bitmask (assigning nil intentionally drops ghost bits).
        # @param column_name [Symbol]
        # @param typecaster [ActiveRecord::Bitwise::Type]
        # @param value [T.untyped]
        # @return [T.untyped] The value to store in the attribute set.
        sig { params(column_name: Symbol, typecaster: ActiveRecord::Bitwise::Type, value: T.untyped).returns(T.untyped) }
        def _bitwise_prepare_value(column_name, typecaster, value) # rubocop:disable Metrics/MethodLength -- main's logic, unchanged
          current_raw = _bitwise_hydrate_raw_cache(column_name)
          casted = typecaster.cast(value)
          if casted.nil?
            _bitwise_raw_cache[column_name] = 0
            nil
          elsif casted.instance_variable_defined?(:@_bitwise_raw_value)
            _bitwise_adopt_raw(column_name, casted, current_raw)
          else
            stamped = casted.dup
            stamped.instance_variable_set(:@_bitwise_raw_value, current_raw)
            stamped.freeze
          end
        end

        # Adopts the raw marker carried by +casted+ (e.g. cast from an Integer). An integer
        # assignment can change only unmapped bits, leaving the flag array equal to the
        # old one; dirty tracking is forced so the raw value is actually persisted on save.
        # @param column_name [Symbol]
        # @param casted [T::Array[T.untyped]]
        # @param current_raw [Integer] The cached raw bitmask before the assignment.
        # @return [T::Array[T.untyped]] +casted+.
        sig { params(column_name: Symbol, casted: T::Array[T.untyped], current_raw: Integer).returns(T::Array[T.untyped]) }
        def _bitwise_adopt_raw(column_name, casted, current_raw)
          new_raw = _bitwise_coerce_raw(casted.instance_variable_get(:@_bitwise_raw_value))
          attribute_will_change!(column_name.to_s) if new_raw != current_raw
          _bitwise_raw_cache[column_name] = new_raw
          casted
        end

        # Intercepts update_columns (and therefore update_column) so the write is
        # ghost-bit preserving and the raw cache reflects the persisted value,
        # preventing later saves from merging stale "forgotten bits".
        # @param attrs [T.untyped]
        # @return [T.untyped]
        sig { params(attrs: T.untyped).returns(T.untyped) }
        def update_columns(attrs)
          processed, bitwise_keys = _bitwise_stamp_updates(attrs)
          result = super(processed)
          bitwise_keys.each do |column_name|
            typecaster = _bitwise_model.attribute_types[column_name.to_s]
            _bitwise_raw_cache[column_name] = _bitwise_coerce_raw(typecaster.serialize(read_attribute(column_name)))
          end
          result
        end

        # Prepares the flag-array values of +attrs+ for {#update_columns}. Integers and nil are
        # written verbatim (full overwrite / NULL); only flag arrays are stamped so the write
        # preserves forgotten bits.
        # @param attrs [T.untyped] The attributes given to +update_columns+.
        # @return [[T.untyped, T::Array[Symbol]]] The attributes to write and the bitwise columns among them.
        sig { params(attrs: T.untyped).returns([T.untyped, T::Array[Symbol]]) }
        def _bitwise_stamp_updates(attrs) # rubocop:disable Metrics/AbcSize, Metrics/MethodLength -- main's logic, unchanged
          bitwise_keys = T.let([], T::Array[Symbol])
          processed = attrs
          attrs.each do |key, value|
            column_name = key.to_sym
            next unless _bitwise_model.bitwise_definitions.key?(column_name)

            typecaster = _bitwise_model.attribute_types[column_name.to_s]
            next unless typecaster.is_a?(ActiveRecord::Bitwise::Type)

            bitwise_keys << column_name
            next if value.is_a?(Integer) || value.nil?

            processed = processed.dup if processed.equal?(attrs)
            processed[key] = _bitwise_prepare_value(column_name, typecaster, value)
          end
          [processed, bitwise_keys]
        end

        # Duplicated records intentionally drop the source record's unmapped
        # ("forgotten") bits: a dup is a new record and should only carry the flags
        # visible in Ruby, never invisible legacy bits.
        # @param other [T.untyped]
        # @return [T.untyped]
        sig { params(other: T.untyped).returns(T.untyped) }
        def initialize_dup(other)
          result = super
          fresh = T.let({}, T::Hash[Symbol, Integer])
          instance_variable_set(:@_bitwise_raw_values, fresh)
          _bitwise_model.bitwise_definitions.each_key do |column_name|
            fresh[column_name] = 0
            value = read_attribute(column_name)
            write_attribute(column_name, value.map { |v| v }) if value.is_a?(Array)
          end
          result
        end
      end
    end
  end
end
