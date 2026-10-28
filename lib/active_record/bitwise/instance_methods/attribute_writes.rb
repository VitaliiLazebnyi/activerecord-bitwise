# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/instance_methods/raw_cache'
require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/type'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Intercepts every attribute write so that flag arrays are stamped with the raw bitmask of their
      # column, keeping the unmapped ("forgotten") bits through every write path.
      module AttributeWrites
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }
        requires_ancestor { RawCache }

        # Intercepts every attribute write (generated setters, `write_attribute`,
        # `self[:col] = ...`) so bitwise arrays are always stamped with the current
        # raw bitmask. This preserves "forgotten bits" even for write paths that
        # bypass the generated setter.
        # @note Both `_write_attribute` (used by generated writers) and
        #   `write_attribute` (used by `[]=` and direct calls) must be overridden:
        #   modern ActiveRecord writes to the attribute set directly from both.
        # @param attr_name [Symbol, String] The attribute.
        # @param value [Object, nil] The assigned value.
        # @return [Object, nil]
        sig { params(attr_name: Types::Name, value: T.nilable(Object)).returns(T.nilable(Object)) }
        def _write_attribute(attr_name, value)
          super(attr_name, _bitwise_intercept_write(attr_name, value))
        end

        # (see #_write_attribute)
        # @param attr_name [Symbol, String] The attribute.
        # @param value [Object, nil] The assigned value.
        # @return [Object, nil]
        sig { params(attr_name: Types::Name, value: T.nilable(Object)).returns(T.nilable(Object)) }
        def write_attribute(attr_name, value)
          super(attr_name, _bitwise_intercept_write(attr_name, value))
        end

        # Prepares +input+ for storage when +name+ is a bitwise column;
        # returns it untouched otherwise.
        # @param name [Symbol, String] The attribute.
        # @param input [Object, nil] The assigned value.
        # @return [Object, nil]
        sig { params(name: Types::Name, input: T.nilable(Object)).returns(T.nilable(Object)) }
        def _bitwise_intercept_write(name, input)
          column = name.to_sym
          type = _bitwise_type(column)
          type ? _bitwise_prepare_value(column, type, input) : input
        end

        # Casts +value+ and synchronizes the raw bitmask cache:
        # * arrays carrying a raw marker (e.g. cast from an Integer) update the cache;
        # * plain arrays are stamped with the currently cached raw bitmask;
        # * nil clears the cached raw bitmask (assigning nil intentionally drops ghost bits).
        # @param column_name [Symbol]
        # @param typecaster [ActiveRecord::Bitwise::Type]
        # @param value [Object, nil]
        # @return [Array<Symbol, String>, nil] The value to store in the attribute set.
        sig { params(column_name: Symbol, typecaster: Type, value: T.nilable(Object)).returns(T.nilable(Types::Flags)) }
        def _bitwise_prepare_value(column_name, typecaster, value)
          current = _bitwise_hydrate_raw_cache(column_name)
          casted = typecaster.cast(value)
          return _bitwise_forget(column_name) unless casted

          RawMask.stamped?(casted) ? _bitwise_adopt(column_name, casted) : RawMask.stamp(casted.dup, current)
        end

        # Intercepts update_columns (and therefore update_column) so the write is
        # ghost-bit preserving and the raw cache reflects the persisted value,
        # preventing later saves from merging stale "forgotten bits".
        # @param attrs [Hash] The attributes to write.
        # @return [Object, nil] What ActiveRecord returns.
        sig { params(attrs: T::Hash[Types::Name, T.nilable(Object)]).returns(T.nilable(Object)) }
        def update_columns(attrs)
          types = _bitwise_types(attrs.keys)
          result = super(attrs.merge(_bitwise_stamped(attrs, types)))
          types.each { |key, type| _bitwise_refresh(key.to_sym, type) }
          result
        end

        # Duplicated records intentionally drop the source record's unmapped
        # ("forgotten") bits: a dup is a new record and should only carry the flags
        # visible in Ruby, never invisible legacy bits.
        # @param other [ActiveRecord::Base] The record being duplicated.
        # @return [Object] What ActiveRecord returns.
        sig { params(other: ActiveRecord::Base).returns(Object) }
        def initialize_dup(other)
          result = super
          clear_bitwise_raw_values_cache!
          bitwise_definitions.each_key { |column| _bitwise_detach(column) }
          result
        end

        private

        # The bitwise type of +column+, or nil when it is not a bitwise column.
        # @param column [Symbol]
        # @return [ActiveRecord::Bitwise::Type, nil]
        sig { params(column: Symbol).returns(T.nilable(Type)) }
        def _bitwise_type(column)
          type = self.class.attribute_types[column.to_s]
          type if type.is_a?(Type)
        end

        # The bitwise types of those +keys+ that name a bitwise column, in order.
        # @param keys [Array<Symbol, String>] Attribute names.
        # @return [Hash{Symbol, String => ActiveRecord::Bitwise::Type}]
        sig { params(keys: T::Array[Types::Name]).returns(T::Hash[Types::Name, Type]) }
        def _bitwise_types(keys)
          keys.filter_map { |key| (type = _bitwise_type(key.to_sym)) && [key, type] }.to_h
        end

        # The values to write for the bitwise columns among +attrs+.
        # @param attrs [Hash] The attributes to write.
        # @param types [Hash] The bitwise types of the bitwise keys of +attrs+.
        # @return [Hash]
        sig do
          params(attrs: T::Hash[Types::Name, T.nilable(Object)], types: T::Hash[Types::Name, Type])
            .returns(T::Hash[Types::Name, T.nilable(Object)])
        end
        def _bitwise_stamped(attrs, types)
          types.to_h { |key, type| [key, _bitwise_prepare_value(key.to_sym, type, attrs.fetch(key))] }
        end

        # Re-reads the raw bitmask of +column+ after a direct write.
        # @param column [Symbol]
        # @param type [ActiveRecord::Bitwise::Type] The bitwise type of the column.
        # @return [Integer]
        sig { params(column: Symbol, type: Type).returns(Integer) }
        def _bitwise_refresh(column, type)
          _bitwise_raw_cache[column] = type.bitmask_of(read_attribute(column))
        end

        # Clears the cached raw bitmask of +column_name+ (assigning nil drops the unmapped bits).
        # @param column_name [Symbol]
        # @return [nil]
        sig { params(column_name: Symbol).returns(NilClass) }
        def _bitwise_forget(column_name)
          _bitwise_raw_cache.store(column_name, 0)
          nil
        end

        # Takes over the raw bitmask that +casted+ carries.
        # @param column_name [Symbol]
        # @param casted [Array<Symbol, String>] A flag array carrying a raw marker.
        # @return [Array<Symbol, String>] +casted+.
        sig { params(column_name: Symbol, casted: Types::Flags).returns(Types::Flags) }
        def _bitwise_adopt(column_name, casted)
          cache = _bitwise_raw_cache
          new_raw = _bitwise_coerce_raw(RawMask.read(casted))
          # An integer assignment can change only unmapped bits, leaving the flag
          # array equal to the old one; force dirty tracking so the raw value is
          # actually persisted on save.
          attribute_will_change!(column_name) unless new_raw == cache.fetch(column_name)
          cache[column_name] = new_raw
          casted
        end

        # Forgets the unmapped bits of +column+ and re-stamps its flags (used for duplicates).
        # @param column [Symbol]
        # @return [void]
        sig { params(column: Symbol).void }
        def _bitwise_detach(column)
          _bitwise_raw_cache[column] = 0
          value = read_attribute(column)
          write_attribute(column, Array.new(value)) if value in Array
        end
      end
    end
  end
end
