# typed: strict
# frozen_string_literal: true

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

        requires_ancestor { Kernel }

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
          return nil unless T.unsafe(self).class.bitwise_definitions.key?(column_name)

          typecaster = T.unsafe(self).class.attribute_types.fetch(column_name.to_s)
          typecaster if typecaster.is_a?(ActiveRecord::Bitwise::Type)
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
        def _bitwise_prepare_value(column_name, typecaster, value)
          current_raw = T.unsafe(self)._bitwise_hydrate_raw_cache(column_name)
          casted = typecaster.cast(value)
          return _bitwise_forget_raw(column_name) if casted.nil?
          return _bitwise_adopt_raw(column_name, casted) if RawMask.stamped?(casted)

          RawMask.stamp(casted.dup, current_raw).freeze
        end

        # Assigning nil clears the cached raw bitmask (intentionally dropping ghost bits).
        # @param column_name [Symbol]
        # @return [NilClass]
        sig { params(column_name: Symbol).returns(NilClass) }
        def _bitwise_forget_raw(column_name)
          T.unsafe(self)._bitwise_raw_cache[column_name] = 0
          nil
        end

        # Adopts the raw marker carried by +casted+ (e.g. cast from an Integer). An integer
        # assignment can change only unmapped bits, leaving the flag array equal to the
        # old one; dirty tracking is forced so the raw value is actually persisted on save.
        # @param column_name [Symbol]
        # @param casted [T::Array[T.untyped]]
        # @return [T::Array[T.untyped]] +casted+.
        sig { params(column_name: Symbol, casted: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
        def _bitwise_adopt_raw(column_name, casted)
          cache = T.unsafe(self)._bitwise_raw_cache
          new_raw = RawMask.coerce(RawMask.read(casted))
          T.unsafe(self).__send__(:attribute_will_change!, column_name.to_s) if new_raw != cache.fetch(column_name)
          cache[column_name] = new_raw
          casted
        end

        # Intercepts update_columns (and therefore update_column) so the write is
        # ghost-bit preserving and the raw cache reflects the persisted value,
        # preventing later saves from merging stale "forgotten bits".
        # @param attrs [T.untyped]
        # @return [T.untyped]
        sig { params(attrs: T.untyped).returns(T.untyped) }
        def update_columns(attrs)
          result = super(attrs.to_h { |key, value| [key, _bitwise_update_value(key, value)] })
          attrs.each_key do |key|
            _bitwise_sync_raw_after_update(key.to_sym) if _bitwise_typecaster(key.to_sym)
          end
          result
        end

        # The value to persist for +key+ in {#update_columns}: flag arrays are stamped so the
        # write preserves forgotten bits, while Integers and nil are written verbatim
        # (full overwrite / NULL).
        # @param key [T.untyped]
        # @param value [T.untyped]
        # @return [T.untyped]
        sig { params(key: T.untyped, value: T.untyped).returns(T.untyped) }
        def _bitwise_update_value(key, value)
          typecaster = _bitwise_typecaster(key.to_sym)
          return value if typecaster.nil? || RawMask.integer?(value) || value.nil?

          _bitwise_prepare_value(key.to_sym, typecaster, value)
        end

        # Refreshes the raw cache of +column_name+ from the value just written.
        # @param column_name [Symbol]
        # @return [void]
        sig { params(column_name: Symbol).void }
        def _bitwise_sync_raw_after_update(column_name)
          typecaster = T.must(_bitwise_typecaster(column_name))
          written = typecaster.serialize(T.unsafe(self).read_attribute(column_name))
          T.unsafe(self)._bitwise_raw_cache[column_name] = RawMask.coerce(written)
        end
      end
    end
  end
end
