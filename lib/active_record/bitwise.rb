# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'active_record/bitwise/version'
require 'active_record/bitwise/bitwise_validator'
require 'active_record'

module ActiveRecord
  # The main namespace for the ActiveRecord::Bitwise gem, which provides capabilities
  # to store multiple boolean or enum values in a single integer column.
  module Bitwise
    extend T::Sig

    # Base error class for all ActiveRecord::Bitwise gem exceptions.
    class Error < StandardError; end

    # Exception raised when an unsupported query or operation is attempted.
    class NotSupportedError < Error; end

    # Exception raised at class-definition time for invalid bitwise configuration
    # (bad mappings, method collisions, invalid defaults). Inherits from
    # ArgumentError so existing `rescue ArgumentError` handlers keep working.
    class ConfigurationError < ArgumentError; end

    # Exception raised when a batch operation (`update_all`) receives flag values
    # that are not present in the mapping. Raising loudly prevents a typo from
    # silently zeroing the column for every matched row.
    class UnknownValueError < ArgumentError; end

    # Maximum number of elements accepted in an assigned array (RAM-exhaustion defense).
    MAX_ARRAY_SIZE = 100

    # Highest permitted bit position. Signed BIGINT columns physically cap at bit 62.
    MAX_BIT_POSITION = 62

    # Shared boolean coercion used by the generated single-flag setters so that
    # form-style values ("0", "false", "", "off") disable a flag instead of enabling it.
    BOOLEAN_TYPE = T.let(ActiveModel::Type::Boolean.new, ActiveModel::Type::Boolean)

    # Serializes bitwise values inside a `where`-style conditions hash into their
    # integer bitmask representation (exact-match semantics). Non-bitwise keys and
    # already-integer values pass through untouched.
    # @param klass [T.untyped] The model class owning the bitwise definitions.
    # @param hash [T::Hash[T.untyped, T.untyped]] The conditions hash.
    # @return [T::Hash[T.untyped, T.untyped]] The (possibly copied) conditions hash.
    sig { params(klass: T.untyped, hash: T::Hash[T.untyped, T.untyped]).returns(T::Hash[T.untyped, T.untyped]) }
    def self.serialize_conditions(klass, hash)
      processed = T.let(hash, T::Hash[T.untyped, T.untyped])
      klass.bitwise_definitions.each_key do |column_name|
        [column_name, column_name.to_s].each do |key|
          next unless processed.key?(key)

          value = processed[key]
          next if value.is_a?(Integer) || value.nil?
          next if value.is_a?(Array) && !value.empty? && value.all?(Integer)

          typecaster = klass.attribute_types[column_name.to_s]
          next unless typecaster.is_a?(ActiveRecord::Bitwise::Type)

          casted = typecaster.cast(value) || []
          unknown = casted.reject { |v| typecaster.mapping_strings.include?(v.to_s) }
          if unknown.any?
            Kernel.raise UnknownValueError,
                         "Unknown bitwise value(s) #{unknown.map(&:to_s).inspect} for column #{column_name}"
          end

          processed = processed.dup if processed.equal?(hash)
          processed[key] = typecaster.serialize(casted)
        end
      end
      processed
    end

    # rubocop:disable Metrics/ClassLength
    # Justification: The custom Type class houses all custom serialization, deserialization,
    # and type casting logic for ActiveModel integration, which are highly cohesive
    # and best kept encapsulated in a single type handler.
    class Type < ActiveRecord::Type::Value
      extend T::Sig

      # The column name associated with this type.
      # @return [Symbol]
      sig { returns(Symbol) }
      attr_reader :column_name

      # The mapping of symbol keys to bit position integers.
      # @return [T::Hash[Symbol, Integer]]
      sig { returns(T::Hash[Symbol, Integer]) }
      attr_reader :mapping

      # The default array of values (applied to new records via the attribute API).
      # @return [T::Array[T.any(Symbol, String)]]
      sig { returns(T::Array[T.any(Symbol, String)]) }
      attr_reader :default

      # The bitmask representing all known mapped positions.
      # @return [Integer]
      sig { returns(Integer) }
      attr_reader :known_mask

      # The list of mapping keys converted to strings for Symbol DoS prevention.
      # @return [T::Array[String]]
      sig { returns(T::Array[String]) }
      attr_reader :mapping_strings

      # Initializes the bitwise type cast configuration.
      # @param column_name [T.any(Symbol, String)] The column name.
      # @param mapping [T::Hash[Symbol, Integer]] The mapping of keys to bit positions.
      # @param default [T.nilable(T::Array[T.any(Symbol, String)])] The default values.
      # @return [void]
      sig { params(column_name: T.any(Symbol, String), mapping: T::Hash[Symbol, Integer], default: T.nilable(T::Array[T.any(Symbol, String)])).void }
      def initialize(column_name, mapping, default)
        @column_name = T.let(column_name.to_sym, Symbol)
        @mapping = T.let(mapping, T::Hash[Symbol, Integer])
        @default = T.let(default || [], T::Array[T.any(Symbol, String)])
        @known_mask = T.let(mapping.values.reduce(0) { |mask, pos| mask | (1 << pos) }, Integer)
        @mapping_strings = T.let(mapping.keys.map(&:to_s).freeze, T::Array[String])
        empty = T.let([], T::Array[T.any(Symbol, String)])
        empty.instance_variable_set(:@_bitwise_raw_value, 0)
        @empty_value = T.let(empty.freeze, T::Array[T.any(Symbol, String)])
        super()
      end

      # Casts a value to a frozen array of symbols or strings.
      # @param value [T.untyped] The value to cast.
      # @raise [ArgumentError] When the value cannot be meaningfully cast (Hash, true, false)
      #   or exceeds {MAX_ARRAY_SIZE} elements.
      # @return [T.nilable(T::Array[T.any(Symbol, String)])] The casted array or nil.
      sig { override.params(value: T.untyped).returns(T.nilable(T::Array[T.any(Symbol, String)])) }
      def cast(value)
        return nil if value.nil?
        return deserialize(value) if value.is_a?(Integer)

        return value if value.is_a?(Array) && value.frozen? && value.instance_variable_defined?(:@_bitwise_raw_value)

        if value.is_a?(Hash) || value == true || value == false
          raise ArgumentError, "cannot cast #{value.inspect} to a bitwise flag array for column #{column_name}"
        end

        # A bare numeric string (e.g. from a raw SQLite read) is a bitmask, not a flag name.
        return deserialize(value.to_i) if value.is_a?(String) && !@mapping_strings.include?(value) && value.match?(/\A\d+\z/)

        # Strip empty strings and nil
        arr = Array(value).dup
        arr.reject! { |v| v.nil? || v == '' }

        # Array RAM Exhaustion Defense: Ceil at MAX_ARRAY_SIZE elements
        raise ArgumentError, "Array size cannot exceed #{MAX_ARRAY_SIZE}" if arr.size > MAX_ARRAY_SIZE

        processed = arr.map do |val|
          val_str = val.to_s
          if @mapping_strings.include?(val_str)
            val_str.to_sym
          else
            val_str
          end
        end.uniq(&:to_s)

        # Preserve raw value if present
        raw = if value.is_a?(Array) && value.instance_variable_defined?(:@_bitwise_raw_value)
                value.instance_variable_get(:@_bitwise_raw_value)
              end

        processed.instance_variable_set(:@_bitwise_raw_value, raw) if raw
        processed.freeze
        processed
      end

      # Deserializes a database integer value into an array of symbols or strings.
      # A database NULL deserializes to an empty array; the configured default is
      # applied only to new records (via the attribute API), never resurrected for
      # persisted NULL rows, so getters, scopes, and persistence stay consistent.
      # @param value [T.untyped] The raw value from the database.
      # @return [T::Array[T.any(Symbol, String)]] The array of symbols/strings represented by the bitmask.
      sig { override.params(value: T.untyped).returns(T::Array[T.any(Symbol, String)]) }
      def deserialize(value)
        # The recursion guard is thread-local (not shared instance state), so it is
        # safe on non-GIL runtimes (JRuby/TruffleRuby) and immune to async
        # exceptions leaking the counter.
        depth = T.unsafe(Thread.current[:ar_bitwise_deserialize_depth]) || 0
        raise Error, 'System recursion limit exceeded in deserialize' if depth >= 2

        begin
          Thread.current[:ar_bitwise_deserialize_depth] = depth + 1
          return @empty_value if value.nil?

          if value.is_a?(Array)
            raw = value.instance_variable_defined?(:@_bitwise_raw_value) ? value.instance_variable_get(:@_bitwise_raw_value) : serialize(value)
            array = cast(value)
            raise Error, 'Casting failed' if array.nil?

            array_dup = array.dup
            array_dup.instance_variable_set(:@_bitwise_raw_value, raw)
            return array_dup.freeze
          end

          # SQLite raw string coercion
          raw_value = value.to_i

          array = []
          @mapping.each do |sym, bit_position|
            array << sym if raw_value.anybits?(1 << bit_position)
          end

          array.instance_variable_set(:@_bitwise_raw_value, raw_value)
          array.freeze
          array
        ensure
          Thread.current[:ar_bitwise_deserialize_depth] = depth
        end
      end

      # Serializes an array of symbols into a database integer bitmask, merging
      # any unmapped ("forgotten") bits carried on the array's raw-value marker.
      # @param value [T.untyped] The value to serialize.
      # @return [T.nilable(Integer)] The resulting integer bitmask.
      sig { override.params(value: T.untyped).returns(T.nilable(Integer)) }
      def serialize(value)
        return nil if value.nil?
        return checked(value) if value.is_a?(Integer)

        new_mask = 0
        Array(value).each do |val|
          val_str = val.to_s
          if @mapping_strings.include?(val_str)
            sym = val_str.to_sym
            new_mask |= (1 << T.unsafe(@mapping[sym]))
          end
        end

        raw_val_ivar = if value.is_a?(Array) && value.instance_variable_defined?(:@_bitwise_raw_value)
                         value.instance_variable_get(:@_bitwise_raw_value)
                       else
                         0
                       end
        raw_value = if raw_val_ivar.is_a?(Integer)
                      raw_val_ivar
                    elsif raw_val_ivar.respond_to?(:to_i)
                      raw_val_ivar.to_i
                    else
                      0
                    end

        checked((raw_value & ~@known_mask) | new_mask)
      end

      private

      # Returns +bitmask+ unless it is out of range for a signed 64-bit column (the widest one). SQLite
      # would otherwise store it as a lossy REAL, and the other adapters fail late with their own errors.
      # @param bitmask [Integer]
      # @raise [ActiveModel::RangeError] When +bitmask+ needs more than 64 bits.
      # @return [Integer] +bitmask+.
      sig { params(bitmask: Integer).returns(Integer) }
      def checked(bitmask)
        return bitmask if bitmask.bit_length < 64

        Kernel.raise ActiveModel::RangeError,
                     "#{bitmask} is out of range for column #{column_name}: it must fit a signed 64-bit integer"
      end
    end
    # rubocop:enable Metrics/ClassLength

    # Prepended to ActiveRecord::Relation to make batch updates and hash queries
    # understand bitwise flag arrays.
    module RelationExtension
      extend T::Sig

      # Intercepts update_all to convert bitwise attribute arrays into a
      # ghost-bit-preserving SQL expression: `(COALESCE(col, 0) & ~known_mask) | mask`.
      # Unmapped ("forgotten") bits of every matched row are preserved, matching the
      # behavior of instance-level saves.
      # @raise [UnknownValueError] If the assigned array contains values missing from the mapping.
      # @param updates [T.untyped]
      # @return [T.untyped]
      sig { params(updates: T.untyped).returns(T.untyped) }
      def update_all(updates)
        if updates.is_a?(Hash) && T.unsafe(self).klass.respond_to?(:bitwise_definitions)
          processed_updates = updates.dup
          T.unsafe(self).klass.bitwise_definitions.each_key do |column_name|
            [column_name, column_name.to_s].each do |key|
              next unless processed_updates.key?(key)

              val = processed_updates[key]
              next if val.is_a?(Integer) || val.nil? || val.is_a?(Arel::Nodes::SqlLiteral) || val.is_a?(Arel::Nodes::Node)

              typecaster = T.unsafe(self).klass.attribute_types[column_name.to_s]
              next unless typecaster.is_a?(ActiveRecord::Bitwise::Type)

              casted = typecaster.cast(val) || []
              unknown = casted.reject { |v| typecaster.mapping_strings.include?(v.to_s) }
              if unknown.any?
                Kernel.raise ActiveRecord::Bitwise::UnknownValueError,
                             "Unknown bitwise value(s) #{unknown.map(&:to_s).inspect} for column #{column_name}; refusing to zero unrecognized flags via update_all"
              end

              # Recompute the mask from the flags alone (ignoring any smuggled raw-value
              # marker) so update_all cannot be used to inject arbitrary bits.
              mask = T.unsafe(typecaster.serialize(casted.map { |v| v })).to_i
              quoted_col = T.unsafe(self).klass.connection.quote_column_name(column_name)
              processed_updates[key] = Arel.sql("(COALESCE(#{quoted_col}, 0) & #{~typecaster.known_mask}) | #{mask}")
            end
          end
          super(processed_updates)
        else
          super
        end
      end

      # Intercepts where to transparently serialize bitwise flag arrays into their
      # integer bitmask (exact-match semantics, like Rails' native enum). This keeps
      # ordinary ActiveRecord idioms (`where`, `find_by`, uniqueness validators)
      # working instead of raising.
      # @note Use the generated `with_*`/`without_*` scopes for subset/superset matching;
      #   a hash condition matches the exact bitmask only.
      # @param args [T.untyped]
      # @return [T.untyped]
      sig { params(args: T.untyped).returns(T.untyped) }
      def where(*args)
        if args.first.is_a?(Hash) && T.unsafe(self).klass.respond_to?(:bitwise_definitions)
          args[0] = ActiveRecord::Bitwise.serialize_conditions(T.unsafe(self).klass, T.unsafe(args.first))
        end
        super
      end
    end

    # Prepended to ActiveRecord::QueryMethods::WhereChain to serialize negated
    # bitwise hash conditions the same way as RelationExtension#where.
    module WhereChainExtension
      extend T::Sig

      # Intercepts not to transparently serialize bitwise flag arrays.
      # @param args [T.untyped]
      # @return [T.untyped]
      sig { params(args: T.untyped).returns(T.untyped) }
      def not(*args)
        scope = T.unsafe(self).instance_variable_get(:@scope)
        if args.first.is_a?(Hash) && scope && T.unsafe(scope).klass.respond_to?(:bitwise_definitions)
          args[0] = ActiveRecord::Bitwise.serialize_conditions(T.unsafe(scope).klass, T.unsafe(args.first))
        end
        super
      end
    end

    # Instance-level behavior shared by every model that declares a bitwise column.
    # Included exactly once per inheritance tree by the `bitwise` macro.
    module InstanceMethods
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
      sig { returns(T::Hash[Symbol, Integer]) }
      def _bitwise_raw_cache
        cache = T.unsafe(self).instance_variable_get(:@_bitwise_raw_values)
        unless cache
          cache = {}
          T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, cache)
        end
        cache
      end

      # Hydrates the raw cache for +column_name+ from the attribute's before-type-cast
      # value unless already present, and returns the cached raw integer.
      # @param column_name [Symbol]
      # @return [Integer]
      sig { params(column_name: Symbol).returns(Integer) }
      def _bitwise_hydrate_raw_cache(column_name)
        cache = _bitwise_raw_cache
        unless cache.key?(column_name)
          raw_before = T.unsafe(self).read_attribute_before_type_cast(column_name)
          cache[column_name] = if raw_before.is_a?(Array) && raw_before.instance_variable_defined?(:@_bitwise_raw_value)
                                 _bitwise_coerce_raw(raw_before.instance_variable_get(:@_bitwise_raw_value))
                               else
                                 _bitwise_coerce_raw(raw_before)
                               end
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
        elsif value.respond_to?(:to_i)
          T.unsafe(value).to_i
        else
          0
        end
      end

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
        return value unless T.unsafe(self).class.bitwise_definitions.key?(column_name)

        typecaster = T.unsafe(self).class.attribute_types[attr_name.to_s]
        return value unless typecaster.is_a?(ActiveRecord::Bitwise::Type)

        _bitwise_prepare_value(column_name, typecaster, value)
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
        current_raw = _bitwise_hydrate_raw_cache(column_name)
        casted = typecaster.cast(value)
        if casted.nil?
          _bitwise_raw_cache[column_name] = 0
          nil
        elsif casted.instance_variable_defined?(:@_bitwise_raw_value)
          new_raw = _bitwise_coerce_raw(casted.instance_variable_get(:@_bitwise_raw_value))
          # An integer assignment can change only unmapped bits, leaving the flag
          # array equal to the old one; force dirty tracking so the raw value is
          # actually persisted on save.
          T.unsafe(self).send(:attribute_will_change!, column_name.to_s) if new_raw != current_raw
          _bitwise_raw_cache[column_name] = new_raw
          casted
        else
          stamped = casted.dup
          stamped.instance_variable_set(:@_bitwise_raw_value, current_raw)
          stamped.freeze
        end
      end

      # Intercepts update_columns (and therefore update_column) so the write is
      # ghost-bit preserving and the raw cache reflects the persisted value,
      # preventing later saves from merging stale "forgotten bits".
      # @param attrs [T.untyped]
      # @return [T.untyped]
      sig { params(attrs: T.untyped).returns(T.untyped) }
      def update_columns(attrs)
        bitwise_keys = T.let([], T::Array[Symbol])
        processed = attrs
        attrs.each do |key, value|
          column_name = key.to_sym
          next unless T.unsafe(self).class.bitwise_definitions.key?(column_name)

          typecaster = T.unsafe(self).class.attribute_types[column_name.to_s]
          next unless typecaster.is_a?(ActiveRecord::Bitwise::Type)

          bitwise_keys << column_name
          # Integers and nil are written verbatim (full overwrite / NULL); only
          # flag arrays are stamped so the write preserves forgotten bits.
          next if value.is_a?(Integer) || value.nil?

          processed = processed.dup if processed.equal?(attrs)
          processed[key] = _bitwise_prepare_value(column_name, typecaster, value)
        end
        result = super(processed)
        bitwise_keys.each do |column_name|
          typecaster = T.unsafe(self).class.attribute_types[column_name.to_s]
          _bitwise_raw_cache[column_name] = _bitwise_coerce_raw(typecaster.serialize(T.unsafe(self).read_attribute(column_name)))
        end
        result
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
        T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, fresh)
        T.unsafe(self).class.bitwise_definitions.each_key do |column_name|
          fresh[column_name] = 0
          value = T.unsafe(self).read_attribute(column_name)
          T.unsafe(self).write_attribute(column_name, value.map { |v| v }) if value.is_a?(Array)
        end
        result
      end

      # Shared implementation of the instance-level atomic methods
      # (`add_<singular>!` / `remove_<singular>!`).
      # @note The database update and read-back run inside a transaction with a
      #   row lock. If an *enclosing* transaction is later rolled back, the
      #   in-memory attribute keeps the applied value (like `update_column`);
      #   call `reload` after a rollback if you need the record re-synchronized.
      # @raise [ActiveRecord::ActiveRecordError] When called on a new (unsaved) record.
      # @param column_name [Symbol]
      # @param operation [Symbol] Either :add or :remove.
      # @param values [T::Array[T.untyped]]
      # @return [void]
      sig { params(column_name: Symbol, operation: Symbol, values: T::Array[T.untyped]).void }
      def _bitwise_atomic_update!(column_name, operation, values)
        if T.unsafe(self).new_record?
          Kernel.raise ActiveRecord::ActiveRecordError,
                       "cannot atomically #{operation} #{column_name} on a new record; save the record first"
        end

        T.unsafe(self).class.transaction do
          T.unsafe(self).class.public_send("#{operation}_#{column_name}!", *values, records: T.unsafe(self).id)
          typecaster = T.unsafe(self).class.attribute_types[column_name.to_s]
          plucked = T.unsafe(self).class.where(id: T.unsafe(self).id).lock(true).pluck(column_name).first
          new_raw = _bitwise_coerce_raw(typecaster.serialize(plucked))
          _bitwise_raw_cache[column_name] = new_raw
          T.unsafe(self).write_attribute(column_name, typecaster.deserialize(new_raw))
          T.unsafe(self).clear_attribute_changes([column_name.to_s]) if T.unsafe(self).respond_to?(:clear_attribute_changes)
        end
      end

      # Resets the raw bitmask cache after every save.
      # @return [void]
      sig { void }
      def _reset_bitwise_raw_value_caches
        T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, {})
      end

      # Validates (lazily, on first initialization) that every bitwise column is an
      # integer column whose byte limit can hold the highest mapped bit position.
      # @return [void]
      sig { void }
      def _validate_bitwise_column_type_and_bounds
        if T.unsafe(self).class.instance_variable_defined?(:@_bitwise_columns_validated) &&
           T.unsafe(self).class.instance_variable_get(:@_bitwise_columns_validated) &&
           T.unsafe(self).class.bitwise_definitions.values.all? { |config| config[:validated] }
          return
        end

        all_validated = T.let(true, T::Boolean)
        T.unsafe(self).class.bitwise_definitions.each do |col, config|
          next if T.unsafe(config)[:validated]

          begin
            next unless T.unsafe(self).class.connection.active? && T.unsafe(self).class.table_exists?

            column = T.unsafe(self).class.columns_hash[col.to_s]
            unless column && T.unsafe(column).type == :integer
              Kernel.raise ArgumentError,
                           "Bitwise column #{col} must be an integer database column"
            end

            max_bits = case T.unsafe(column).limit
                       when 1 then 7
                       when 2 then 15
                       when 3 then 23
                       when 4, nil then 31
                       when 8 then 63
                       else 31
                       end

            max_assigned_position = config[:mapping].values.max || 0
            if max_assigned_position >= max_bits
              Kernel.raise ArgumentError,
                           "Bitwise column #{col} has limit of #{T.unsafe(column).limit || 4} bytes (max #{max_bits} flags), but mapping requires bit shift position #{max_assigned_position}."
            end

            T.unsafe(config)[:validated] = true
          rescue ArgumentError => e
            Kernel.raise e
          rescue StandardError
            all_validated = false
            # Ignore database missing errors
          end
        end

        return unless all_validated && T.unsafe(self).class.bitwise_definitions.present?

        T.unsafe(self).class.instance_variable_set(:@_bitwise_columns_validated, true)
      end
    end

    # Included/extended in ActiveRecord models to provide macro bitwise capabilities
    #
    # @!method self.add_column!(*values, records:)
    #   Class-level atomic method to add values to specific records.
    # @!method self.remove_column!(*values, records:)
    #   Class-level atomic method to remove values from specific records.
    # @!scope class
    #   @!method with_column(*values)
    #     Scope to find records with all specified values.
    #   @!method with_any_column(*values)
    #     Scope to find records with any of the specified values.
    #   @!method with_exact_column(*values)
    #     Scope to find records with exactly the specified values.
    #   @!method without_column(*values)
    #     Scope to find records without any of the specified values.
    # @!method add_singular!(*values)
    #   Instance-level atomic method to add values.
    #   @note This method wraps the database update in a transaction and uses locking to prevent TOCTOU races.
    # @!method add_column!(*values)
    #   Alias for add_singular! (only generated when the singular differs from the column name).
    # @!method remove_singular!(*values)
    #   Instance-level atomic method to remove values.
    #   @note This method wraps the database update in a transaction and uses locking to prevent TOCTOU races.
    # @!method remove_column!(*values)
    #   Alias for remove_singular! (only generated when the singular differs from the column name).
    module Model
      extend T::Sig

      # Defines bitwise attributes, getters, setters, scopes, and helper methods.
      # @param column_name [T.any(Symbol, String)] The database column name.
      # @param mapping [T.any(T::Hash[T.any(Symbol, String), T.any(Integer, String)], T::Array[T.any(Symbol, String)])] The enum/boolean value mapping.
      #   Hash values are bit *positions* (`1 << position`), not masks.
      # @param default [T.nilable(T::Array[T.any(Symbol, String)])] Optional default values (must be present in the mapping).
      # @param prefix [T.nilable(T.any(Symbol, String, T::Boolean))] Optional prefix for method names.
      # @param suffix [T.nilable(T.any(Symbol, String, T::Boolean))] Optional suffix for method names.
      # @raise [ConfigurationError] On invalid mappings, defaults, or method collisions.
      # @return [void]
      sig do
        params(
          column_name: T.any(Symbol, String),
          mapping: T.any(T::Hash[T.any(Symbol, String), T.any(Integer, String)], T::Array[T.any(Symbol, String)]),
          default: T.nilable(T::Array[T.any(Symbol, String)]),
          prefix: T.nilable(T.any(Symbol, String, T::Boolean)),
          suffix: T.nilable(T.any(Symbol, String, T::Boolean))
        ).void
      end
      def bitwise(column_name, mapping, default: nil, prefix: nil, suffix: nil)
        normalized_mapping = _bitwise_normalize_mapping(column_name, mapping)
        mapping_strings = normalized_mapping.keys.map(&:to_s)

        default_val = default || []
        invalid_defaults = default_val.reject { |v| mapping_strings.include?(v.to_s) }
        if invalid_defaults.any?
          Kernel.raise ConfigurationError,
                       "Bitwise column #{column_name} default contains values not present in the mapping: #{invalid_defaults.map(&:to_s).inspect}"
        end

        prefix_str = _bitwise_affix(column_name, prefix, :prefix)
        suffix_str = _bitwise_affix(column_name, suffix, :suffix)
        generated_methods = _bitwise_check_collisions!(column_name, normalized_mapping, prefix_str, suffix_str)

        T.unsafe(self).bitwise_definitions = T.unsafe(self).bitwise_definitions.dup
        T.unsafe(self).bitwise_definitions[column_name.to_sym] = {
          mapping: normalized_mapping,
          default: default_val,
          prefix: prefix,
          suffix: suffix,
          validated: false,
          generated_methods: generated_methods
        }

        T.unsafe(self).attribute column_name, ActiveRecord::Bitwise::Type.new(column_name, normalized_mapping, default_val), default: default_val

        _bitwise_define_getter(column_name)
        _bitwise_define_flag_methods(column_name, normalized_mapping, prefix_str, suffix_str)
        _bitwise_define_atomic_methods(column_name, normalized_mapping, mapping_strings)
        _bitwise_define_scopes(column_name, normalized_mapping, mapping_strings)

        # Register instance behavior and callbacks exactly once per inheritance tree.
        unless T.unsafe(self) <= ActiveRecord::Bitwise::InstanceMethods
          T.unsafe(self).include(ActiveRecord::Bitwise::InstanceMethods)
          T.unsafe(self).after_initialize :_validate_bitwise_column_type_and_bounds
          T.unsafe(self).after_save :_reset_bitwise_raw_value_caches
        end
        nil
      end

      # Returns a copy of the mapping schema for the specified bitwise column.
      # @param col [T.any(Symbol, String)] The column name.
      # @return [T.nilable(T::Hash[Symbol, Integer])]
      sig { params(col: T.any(Symbol, String)).returns(T.nilable(T::Hash[Symbol, Integer])) }
      def bitwise_schema(col)
        T.unsafe(self).bitwise_definitions.dig(col.to_sym, :mapping)&.dup
      end

      # Gives every subclass its own deep copy of the bitwise definitions so a
      # subclass (or a spec) mutating its configuration can never leak state into
      # the parent class or into sibling subclasses.
      # @param subclass [T.untyped]
      # @return [void]
      sig { params(subclass: T.untyped).void }
      def inherited(subclass)
        super
        definitions = T.unsafe(self).bitwise_definitions
        return if definitions.blank?

        T.unsafe(subclass).bitwise_definitions = definitions.transform_values do |config|
          copied = config.dup
          copied[:mapping] = config[:mapping].dup
          copied
        end
      end

      # Automatically extends the base class with the bitwise definitions attribute.
      # Guarded so extending a subclass never wipes definitions inherited from a parent.
      # @param base [T::Module[T.anything]] The class extending this module.
      # @return [void]
      sig { params(base: T::Module[T.anything]).void }
      def self.extended(base)
        T.unsafe(base).class_attribute :bitwise_definitions, default: {} unless T.unsafe(base).respond_to?(:bitwise_definitions)
      end

      private

      # Normalizes and validates a mapping into `{Symbol => Integer position}`.
      # @param column_name [T.any(Symbol, String)]
      # @param mapping [T.untyped]
      # @raise [ConfigurationError] On non-integer, negative, out-of-range, or duplicate positions.
      # @return [T::Hash[Symbol, Integer]]
      sig { params(column_name: T.any(Symbol, String), mapping: T.untyped).returns(T::Hash[Symbol, Integer]) }
      def _bitwise_normalize_mapping(column_name, mapping)
        normalized = if mapping.is_a?(Array)
                       mapping.each_with_index.with_object({}) do |(k, idx), h|
                         h[k.to_sym] = _bitwise_normalize_position(column_name, k, idx)
                       end
                     elsif mapping.is_a?(Hash)
                       mapping.each_with_object({}) { |(k, v), h| h[k.to_sym] = _bitwise_normalize_position(column_name, k, v) }
                     else
                       Kernel.raise ArgumentError, 'Mapping must be a Hash or an Array'
                     end

        if normalized.size != mapping.size
          Kernel.raise ConfigurationError, "Bitwise column #{column_name} mapping contains duplicate keys after symbolization"
        end
        if normalized.values.uniq.size != normalized.size
          Kernel.raise ConfigurationError,
                       "Bitwise column #{column_name} mapping assigns the same bit position to multiple keys: #{normalized.inspect}. " \
                       'Values are bit POSITIONS (1 << position), not masks.'
        end

        normalized
      end

      # Validates a single mapping value as a bit position.
      # @param column_name [T.any(Symbol, String)]
      # @param key [T.untyped]
      # @param value [T.untyped]
      # @raise [ConfigurationError] When the value is not a usable bit position.
      # @return [Integer]
      sig { params(column_name: T.any(Symbol, String), key: T.untyped, value: T.untyped).returns(Integer) }
      def _bitwise_normalize_position(column_name, key, value)
        position = case value
                   when Integer then value
                   when String then value.match?(/\A\d+\z/) ? value.to_i : nil
                   end
        unless position && position >= 0 && position <= MAX_BIT_POSITION
          Kernel.raise ConfigurationError,
                       "Bitwise column #{column_name} mapping key #{key} has invalid bit position #{value.inspect}. " \
                       "Positions must be Integers between 0 and #{MAX_BIT_POSITION}; they are bit POSITIONS (1 << position), not masks."
        end
        position
      end

      # Computes the method name prefix/suffix string.
      # @param column_name [T.any(Symbol, String)]
      # @param affix [T.untyped]
      # @param kind [Symbol] Either :prefix or :suffix.
      # @return [String]
      sig { params(column_name: T.any(Symbol, String), affix: T.untyped, kind: Symbol).returns(String) }
      def _bitwise_affix(column_name, affix, kind)
        base = case affix
               when true then T.unsafe(column_name.to_s).singularize
               when Symbol, String then affix.to_s
               else return ''
               end
        kind == :prefix ? "#{base}_" : "_#{base}"
      end

      # Verifies that every generated flag method is safe to define: no clobbering of
      # core ActiveRecord methods, of methods generated by other bitwise columns, or
      # of real database columns. Returns the list of generated method names.
      # @param column_name [T.any(Symbol, String)]
      # @param normalized_mapping [T::Hash[Symbol, Integer]]
      # @param prefix_str [String]
      # @param suffix_str [String]
      # @raise [ArgumentError] On a collision with core ActiveRecord::Base methods.
      # @raise [ConfigurationError] On a collision with another bitwise column or a database column.
      # @return [T::Array[String]]
      sig { params(column_name: T.any(Symbol, String), normalized_mapping: T::Hash[Symbol, Integer], prefix_str: String, suffix_str: String).returns(T::Array[String]) }
      def _bitwise_check_collisions!(column_name, normalized_mapping, prefix_str, suffix_str)
        core_methods = ActiveRecord::Base.instance_methods +
                       ActiveRecord::Base.private_instance_methods +
                       ActiveRecord::Base.protected_instance_methods

        other_generated = T.unsafe(self).bitwise_definitions.flat_map do |col, config|
          col == column_name.to_sym ? [] : Kernel.Array(config[:generated_methods])
        end

        table_columns = begin
          T.unsafe(self).table_exists? ? T.unsafe(self).column_names : []
        rescue StandardError
          []
        end

        generated_methods = T.let([], T::Array[String])
        normalized_mapping.each_key do |key|
          method_name = "#{prefix_str}#{key}#{suffix_str}"

          if method_name == column_name.to_s || T.unsafe(self).bitwise_definitions.key?(method_name.to_sym) || table_columns.include?(method_name)
            Kernel.raise ConfigurationError,
                         "Bitwise column #{column_name} mapping key #{key} would shadow the database column or attribute '#{method_name}'. " \
                         'Use prefix:/suffix: to disambiguate.'
          end

          ["#{method_name}?", "#{method_name}=", "#{method_name}!"].each do |m|
            if core_methods.include?(m.to_sym)
              Kernel.raise ArgumentError,
                           "Bitwise column #{column_name} mapping key #{key} generates method ##{m} which collides with core ActiveRecord::Base instance methods."
            end
            if other_generated.include?(m)
              Kernel.raise ConfigurationError,
                           "Bitwise column #{column_name} mapping key #{key} generates method ##{m} which is already defined by another bitwise column. " \
                           'Use prefix:/suffix: to disambiguate.'
            end
            generated_methods << m
          end
        end
        generated_methods
      end

      # Defines the column getter that stamps returned arrays with the raw bitmask.
      # @param column_name [T.any(Symbol, String)]
      # @return [void]
      sig { params(column_name: T.any(Symbol, String)).void }
      def _bitwise_define_getter(column_name)
        column_sym = column_name.to_sym
        T.unsafe(self).define_method(column_name) do
          raw = T.unsafe(self)._bitwise_hydrate_raw_cache(column_sym)
          val = super()
          val = T.unsafe(self).class.attribute_types[column_name.to_s].deserialize(nil) if val.nil?

          if val.is_a?(Array) && (!val.frozen? || !val.instance_variable_defined?(:@_bitwise_raw_value))
            stamped = val.dup
            stamped.instance_variable_set(:@_bitwise_raw_value, raw)
            val = stamped.freeze
          end
          val
        end
      end

      # Defines the per-flag `flag?`, `flag=`, and `flag!` methods.
      # @param column_name [T.any(Symbol, String)]
      # @param normalized_mapping [T::Hash[Symbol, Integer]]
      # @param prefix_str [String]
      # @param suffix_str [String]
      # @return [void]
      sig { params(column_name: T.any(Symbol, String), normalized_mapping: T::Hash[Symbol, Integer], prefix_str: String, suffix_str: String).void }
      def _bitwise_define_flag_methods(column_name, normalized_mapping, prefix_str, suffix_str)
        normalized_mapping.each_key do |key|
          method_name = "#{prefix_str}#{key}#{suffix_str}"

          T.unsafe(self).define_method("#{method_name}?") do
            current_values = Kernel.Array(T.unsafe(self).public_send(column_name))
            current_values.include?(key)
          end

          # Uses ActiveModel boolean semantics: "0", "false", "", "off", 0 disable the
          # flag (matching Rails checkbox conventions) instead of raw Ruby truthiness.
          T.unsafe(self).define_method("#{method_name}=") do |val|
            enabled = ActiveRecord::Bitwise::BOOLEAN_TYPE.cast(val)
            original_array = T.unsafe(self).public_send(column_name)
            current_values = Kernel.Array(original_array).dup
            if original_array.is_a?(Array) && original_array.instance_variable_defined?(:@_bitwise_raw_value)
              current_values.instance_variable_set(:@_bitwise_raw_value, original_array.instance_variable_get(:@_bitwise_raw_value))
            end
            if enabled
              current_values << key unless current_values.include?(key)
            else
              current_values.delete(key)
            end
            T.unsafe(self).public_send("#{column_name}=", current_values)
          end

          # @note This is a convenience wrapper that performs a full `save!` cycle
          #   (validations, callbacks, dirty tracking). It is NOT an atomic SQL operation.
          #   If a validation on another attribute fails, this will raise
          #   `ActiveRecord::RecordInvalid`. For truly atomic operations, use the
          #   instance-level `add_<singular>!` method instead.
          T.unsafe(self).define_method("#{method_name}!") do
            current_values = Kernel.Array(T.unsafe(self).public_send(column_name)).dup
            current_values << key unless current_values.include?(key)
            T.unsafe(self).public_send("#{column_name}=", current_values)
            T.unsafe(self).save!
          end
        end
      end

      # Defines the class-level and instance-level atomic add/remove methods.
      # @param column_name [T.any(Symbol, String)]
      # @param normalized_mapping [T::Hash[Symbol, Integer]]
      # @param mapping_strings [T::Array[String]]
      # @return [void]
      sig { params(column_name: T.any(Symbol, String), normalized_mapping: T::Hash[Symbol, Integer], mapping_strings: T::Array[String]).void }
      def _bitwise_define_atomic_methods(column_name, normalized_mapping, mapping_strings)
        T.unsafe(self).singleton_class.class_eval do
          %i[add remove].each do |operation|
            T.unsafe(self).define_method("#{operation}_#{column_name}!") do |*values, records:|
              ids = Kernel.Array(records).map { |r| r.respond_to?(:id) ? T.unsafe(r).id : r }
              return if ids.empty?

              mask = values.flatten.filter_map do |v|
                val_str = v.to_s
                mapping_strings.include?(val_str) ? normalized_mapping[val_str.to_sym] : nil
              end.reduce(0) { |m, pos| m | (1 << pos) }
              return if mask.zero?

              quoted_col = T.unsafe(self).connection.quote_column_name(column_name)
              sql = if operation == :add
                      "#{quoted_col} = COALESCE(#{quoted_col}, 0) | ?"
                    else
                      "#{quoted_col} = COALESCE(#{quoted_col}, 0) - (COALESCE(#{quoted_col}, 0) & ?)"
                    end
              T.unsafe(self).where(id: ids).update_all([sql, mask])
            end
          end
        end

        # Instance-level atomic methods. When the column name is already singular
        # (or uncountable), only one method is defined — defining an alias with the
        # same name would overwrite the implementation and recurse infinitely.
        singular_col = T.unsafe(column_name.to_s).singularize
        column_sym = column_name.to_sym

        %i[add remove].each do |operation|
          impl_name = "#{operation}_#{singular_col}!"
          T.unsafe(self).define_method(impl_name) do |*values|
            T.unsafe(self)._bitwise_atomic_update!(column_sym, operation, values)
          end

          alias_name = "#{operation}_#{column_name}!"
          next if alias_name == impl_name

          T.unsafe(self).define_method(alias_name) do |*values|
            T.unsafe(self).send(impl_name, *values)
          end
        end
      end

      # Defines the four query scopes. Column references are table-qualified so the
      # scopes remain unambiguous under joins.
      # @note `with_` and `with_any_` silently drop unrecognized values, returning
      #   `where('1=0')` (empty) only if ALL values are invalid. `with_exact_` returns
      #   `where('1=0')` if ANY value is invalid (strict validation). `without_` drops
      #   unrecognized values and returns `all` if none are valid.
      # @param column_name [T.any(Symbol, String)]
      # @param normalized_mapping [T::Hash[Symbol, Integer]]
      # @param mapping_strings [T::Array[String]]
      # @return [void]
      sig { params(column_name: T.any(Symbol, String), normalized_mapping: T::Hash[Symbol, Integer], mapping_strings: T::Array[String]).void }
      def _bitwise_define_scopes(column_name, normalized_mapping, mapping_strings)
        qualified_col = Kernel.lambda do |scope|
          "#{T.unsafe(scope).connection.quote_table_name(T.unsafe(scope).table_name)}.#{T.unsafe(scope).connection.quote_column_name(column_name)}"
        end

        T.unsafe(self).scope "with_#{column_name}", Kernel.lambda { |*values|
          return T.unsafe(self).all if values.empty?

          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          quoted_col = qualified_col.call(self)
          if cleaned.include?(0) || cleaned.include?('0') || cleaned.empty?
            return T.unsafe(self).where("COALESCE(#{quoted_col}, 0) = 0")
          end

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }
          return T.unsafe(self).where('1=0') if valid.empty?

          mask = valid.reduce(0) { |m, v| m | (1 << T.must(normalized_mapping[v])) }
          T.unsafe(self).where("#{quoted_col} & ? = ?", mask, mask)
        }

        T.unsafe(self).scope "with_any_#{column_name}", Kernel.lambda { |*values|
          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          return T.unsafe(self).all if cleaned.empty?

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }
          return T.unsafe(self).where('1=0') if valid.empty?

          mask = valid.reduce(0) { |m, v| m | (1 << T.must(normalized_mapping[v])) }
          T.unsafe(self).where("#{qualified_col.call(self)} & ? > 0", mask)
        }

        T.unsafe(self).scope "with_exact_#{column_name}", Kernel.lambda { |*values|
          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          quoted_col = qualified_col.call(self)

          return T.unsafe(self).where("COALESCE(#{quoted_col}, 0) = 0") if cleaned.empty?

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }

          return T.unsafe(self).where('1=0') if valid.size < cleaned.size

          mask = valid.reduce(0) { |m, v| m | (1 << T.must(normalized_mapping[v])) }
          T.unsafe(self).where("#{quoted_col} = ?", mask)
        }

        T.unsafe(self).scope "without_#{column_name}", Kernel.lambda { |*values|
          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          return T.unsafe(self).all if cleaned.empty?

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }
          return T.unsafe(self).all if valid.empty?

          mask = valid.reduce(0) { |m, v| m | (1 << T.must(normalized_mapping[v])) }
          T.unsafe(self).where("COALESCE(#{qualified_col.call(self)}, 0) & ? = 0", mask)
        }
      end
    end
  end
end

T.unsafe(ActiveSupport).on_load(:active_record) do
  extend ActiveRecord::Bitwise::Model
  ActiveRecord::Relation.prepend(ActiveRecord::Bitwise::RelationExtension)
  ActiveRecord::QueryMethods::WhereChain.prepend(ActiveRecord::Bitwise::WhereChainExtension)
end
