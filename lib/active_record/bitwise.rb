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
    # Base error class for all ActiveRecord::Bitwise gem exceptions.
    class Error < StandardError; end

    # Exception raised when an unsupported query or operation is attempted.
    class NotSupportedError < Error; end

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

      # The default array of values.
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
        @deserializing_depth = T.let(0, Integer)
        super()
      end

      # Casts a value to a frozen array of symbols or strings.
      # @param value [T.untyped] The value to cast.
      # @return [T.nilable(T::Array[T.any(Symbol, String)])] The casted array or nil.
      sig { override.params(value: T.untyped).returns(T.nilable(T::Array[T.any(Symbol, String)])) }
      def cast(value)
        return nil if value.nil?
        return deserialize(value) if value.is_a?(Integer)

        return value if value.is_a?(Array) && value.frozen? && value.instance_variable_defined?(:@_bitwise_raw_value)

        # Strip empty strings and nil
        arr = Kernel.Array(value).dup
        arr.reject! { |v| v.nil? || v == '' }

        # Array RAM Exhaustion Defense: Ceil at 100 elements
        Kernel.raise ArgumentError, 'Array size cannot exceed 100' if arr.size > 100

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
      # @param value [T.untyped] The raw value from the database.
      # @return [T::Array[T.any(Symbol, String)]] The array of symbols/strings represented by the bitmask.
      sig { override.params(value: T.untyped).returns(T::Array[T.any(Symbol, String)]) }
      def deserialize(value)
        if @deserializing_depth >= 2
          Kernel.raise Error, 'System recursion limit exceeded in deserialize'
        end

        @deserializing_depth += 1
        begin
          if value.nil?
            return [] unless default.any?

            default_mask = 0
            default.each do |val|
              pos = @mapping[val.to_s.to_sym]
              default_mask |= (1 << pos) if pos
            end
            return deserialize(default_mask)
          end

          if value.is_a?(Array)
            raw = value.instance_variable_defined?(:@_bitwise_raw_value) ? value.instance_variable_get(:@_bitwise_raw_value) : serialize(value)
            array = cast(value)
            Kernel.raise Error, 'Casting failed' if array.nil?
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
          @deserializing_depth -= 1
        end
      end

      # Serializes an array of symbols into a database integer bitmask.
      # @param value [T.untyped] The value to serialize.
      # @return [T.nilable(Integer)] The resulting integer bitmask.
      sig { override.params(value: T.untyped).returns(T.nilable(Integer)) }
      def serialize(value)
        return nil if value.nil?
        return value if value.is_a?(Integer)

        new_mask = 0
        Kernel.Array(value).each do |val|
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

        (raw_value & ~@known_mask) | new_mask
      end
    end
    # rubocop:enable Metrics/ClassLength

    # Prepended to ActiveRecord::Relation to handle batch updates and where poisoning
    module RelationExtension
      extend T::Sig

      # Intercepts update_all to serialize bitwise attribute arrays to integers before updating.
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
              next if val.is_a?(Integer)

              typecaster = T.unsafe(self).klass.attribute_types[column_name.to_s]
              processed_updates[key] = typecaster.serialize(typecaster.cast(val)) if typecaster.is_a?(ActiveRecord::Bitwise::Type)
            end
          end
          super(processed_updates)
        else
          super
        end
      end

      # Intercepts where to prevent direct querying of bitwise columns.
      # @note This guard only catches Hash-based queries. Arel-based queries (e.g.,
      #   `User.where(User.arel_table[:roles].eq(1))`) bypass this check by design,
      #   since Arel users are assumed to understand bitmask semantics.
      # @param args [T.untyped]
      # @return [T.untyped]
      sig { params(args: T.untyped).returns(T.untyped) }
      def where(*args)
        check_bitwise_query!(args.first) if args.first.is_a?(Hash) && T.unsafe(self).klass.respond_to?(:bitwise_definitions)
        super
      end

      private

      # Validates that bitwise columns are not directly queried.
      # @param hash [T::Hash[T.untyped, T.untyped]]
      # @return [void]
      sig { params(hash: T::Hash[T.untyped, T.untyped]).void }
      def check_bitwise_query!(hash)
        T.unsafe(self).klass.bitwise_definitions.each_key do |column_name|
          [column_name, column_name.to_s].each do |key|
            if hash.key?(key)
              Kernel.raise ActiveRecord::Bitwise::NotSupportedError,
                           "Direct querying of bitwise column #{column_name} via where is not supported. Use with_#{column_name} or without_#{column_name} scopes instead."
            end
          end
        end
      end
    end

    # Prepended to ActiveRecord::QueryMethods::WhereChain to handle negation where poisoning
    module WhereChainExtension
      extend T::Sig

      # Intercepts not to prevent direct querying of negated bitwise columns.
      # @param args [T.untyped]
      # @return [T.untyped]
      sig { params(args: T.untyped).returns(T.untyped) }
      def not(*args)
        scope = T.unsafe(self).instance_variable_get(:@scope)
        if args.first.is_a?(Hash) && scope && T.unsafe(scope).klass.respond_to?(:bitwise_definitions)
          T.unsafe(scope).klass.bitwise_definitions.each_key do |column_name|
            [column_name, column_name.to_s].each do |key|
              if args.first.key?(key)
                Kernel.raise ActiveRecord::Bitwise::NotSupportedError,
                             "Direct querying of bitwise column #{column_name} via where.not is not supported. Use without_#{column_name} scope instead."
              end
            end
          end
        end
        super
      end
    end

    # Included/extended in ActiveRecord models to provide macro bitwise capabilities
    #
    # @!method self.add_column!(*values, records:)
    #   Class-level atomic method to add values to specific records.
    # @!method self.remove_column!(*values, records:)
    #   Class-level atomic method to remove values from specific records.
    # @!method self.bitwise_schema(col)
    #   Returns the mapping schema for the specified bitwise column.
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
    #   Alias for add_singular!.
    # @!method remove_singular!(*values)
    #   Instance-level atomic method to remove values.
    #   @note This method wraps the database update in a transaction and uses locking to prevent TOCTOU races.
    # @!method remove_column!(*values)
    #   Alias for remove_singular!.
    module Model
      extend T::Sig

      # Defines bitwise attributes, getters, setters, scopes, and helper methods.
      # @param column_name [T.any(Symbol, String)] The database column name.
      # @param mapping [T.any(T::Hash[T.any(Symbol, String), T.any(Integer, String)], T::Array[T.any(Symbol, String)])] The enum/boolean value mapping.
      # @param default [T.nilable(T::Array[T.any(Symbol, String)])] Optional default values.
      # @param prefix [T.nilable(T.any(Symbol, String, T::Boolean))] Optional prefix for method names.
      # @param suffix [T.nilable(T.any(Symbol, String, T::Boolean))] Optional suffix for method names.
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
        normalized_mapping = if mapping.is_a?(Array)
                               mapping.each_with_index.with_object({}) { |(k, idx), h| h[k.to_sym] = idx }
                             elsif mapping.is_a?(Hash)
                               mapping.each_with_object({}) { |(k, v), h| h[k.to_sym] = v.to_i }
                             else
                               Kernel.raise ArgumentError, 'Mapping must be a Hash or an Array'
                             end

        default_val = default || []
        mapping_strings = normalized_mapping.keys.map(&:to_s)
        T.unsafe(self).bitwise_definitions = T.unsafe(self).bitwise_definitions.dup
        T.unsafe(self).bitwise_definitions[column_name.to_sym] = {
          mapping: normalized_mapping,
          default: default_val,
          prefix: prefix,
          suffix: suffix,
          validated: false
        }

        T.unsafe(self).attribute column_name, ActiveRecord::Bitwise::Type.new(column_name, normalized_mapping, default_val), default: default_val

        # Define getter
        T.unsafe(self).define_method(column_name) do
          raw_values = T.unsafe(self).instance_variable_get(:@_bitwise_raw_values)
          unless raw_values
            raw_values = {}
            T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, raw_values)
          end

          unless raw_values.key?(column_name.to_sym)
            raw_before = T.unsafe(self).read_attribute_before_type_cast(column_name)
            raw_values[column_name.to_sym] = if raw_before.is_a?(Integer)
                                               raw_before
                                             elsif raw_before.respond_to?(:to_i)
                                               raw_before.to_i
                                             else
                                               0
                                             end
          end

          val = super()
          val = T.unsafe(self).class.attribute_types[column_name.to_s].deserialize(nil) if val.nil?

          if val.is_a?(Array) && !val.frozen?
            val = val.dup
            val.instance_variable_set(:@_bitwise_raw_value, raw_values[column_name.to_sym])
            val.freeze
          elsif val.is_a?(Array) && val.frozen? && !val.instance_variable_defined?(:@_bitwise_raw_value)
            unfrozen = val.dup
            unfrozen.instance_variable_set(:@_bitwise_raw_value, raw_values[column_name.to_sym])
            unfrozen.freeze
            val = unfrozen
          end
          val
        end

        # Define setter
        T.unsafe(self).define_method("#{column_name}=") do |new_value|
          raw_values = T.unsafe(self).instance_variable_get(:@_bitwise_raw_values)
          unless raw_values
            raw_values = {}
            T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, raw_values)
          end

          unless raw_values.key?(column_name.to_sym)
            raw_before = T.unsafe(self).read_attribute_before_type_cast(column_name)
            raw_values[column_name.to_sym] = if raw_before.is_a?(Integer)
                                               raw_before
                                             elsif raw_before.respond_to?(:to_i)
                                               raw_before.to_i
                                             else
                                               0
                                             end
          end

          current_raw = raw_values[column_name.to_sym]
          typecaster = T.unsafe(self).class.attribute_types[column_name.to_s]
          casted = typecaster.cast(new_value)

          if casted.is_a?(Array)
            unfrozen = casted.dup
            unfrozen.instance_variable_set(:@_bitwise_raw_value, current_raw)
            unfrozen.freeze
            casted = unfrozen
          end

          super(casted)
        end

        # Define prefix/suffix methods
        prefix_str = case prefix
                     when true then "#{T.unsafe(column_name.to_s).singularize}_"
                     when Symbol, String then "#{prefix}_"
                     else ''
                     end

        suffix_str = case suffix
                     when true then "_#{T.unsafe(column_name.to_s).singularize}"
                     when Symbol, String then "_#{suffix}"
                     else ''
                     end

        conflicting_methods = ActiveRecord::Base.instance_methods +
                              ActiveRecord::Base.private_instance_methods +
                              ActiveRecord::Base.protected_instance_methods

        normalized_mapping.each_key do |key|
          method_name = "#{prefix_str}#{key}#{suffix_str}"

          # Assert method collisions
          generated = ["#{method_name}?", "#{method_name}=", "#{method_name}!"]
          generated.each do |m|
            if conflicting_methods.include?(m.to_sym)
              Kernel.raise ArgumentError,
                           "Bitwise column #{column_name} mapping key #{key} generates method ##{m} which collides with core ActiveRecord::Base instance methods."
            end
          end

          T.unsafe(self).define_method("#{method_name}?") do
            current_values = Kernel.Array(T.unsafe(self).public_send(column_name))
            current_values.include?(key)
          end

          T.unsafe(self).define_method("#{method_name}=") do |val|
            original_array = T.unsafe(self).public_send(column_name)
            current_values = Kernel.Array(original_array).dup
            if original_array.is_a?(Array) && original_array.instance_variable_defined?(:@_bitwise_raw_value)
              current_values.instance_variable_set(:@_bitwise_raw_value, original_array.instance_variable_get(:@_bitwise_raw_value))
            end
            if val
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

        T.unsafe(self).singleton_class.class_eval do
          T.unsafe(self).define_method("add_#{column_name}!") do |*values, records:|
            ids = Kernel.Array(records).map { |r| r.respond_to?(:id) ? T.unsafe(r).id : r }
            return if ids.empty?

            mask = values.flatten.filter_map do |v|
              val_str = v.to_s
              mapping_strings.include?(val_str) ? normalized_mapping[val_str.to_sym] : nil
            end.reduce(0) { |m, pos| m | (1 << pos) }
            return if mask.zero?

            quoted_col = T.unsafe(self).connection.quote_column_name(column_name)
            T.unsafe(self).where(id: ids).update_all(["#{quoted_col} = COALESCE(#{quoted_col}, 0) | ?", mask])
          end

          T.unsafe(self).define_method("remove_#{column_name}!") do |*values, records:|
            ids = Kernel.Array(records).map { |r| r.respond_to?(:id) ? T.unsafe(r).id : r }
            return if ids.empty?

            mask = values.flatten.filter_map do |v|
              val_str = v.to_s
              mapping_strings.include?(val_str) ? normalized_mapping[val_str.to_sym] : nil
            end.reduce(0) { |m, pos| m | (1 << pos) }
            return if mask.zero?

            quoted_col = T.unsafe(self).connection.quote_column_name(column_name)
            T.unsafe(self).where(id: ids).update_all(["#{quoted_col} = COALESCE(#{quoted_col}, 0) - (COALESCE(#{quoted_col}, 0) & ?)", mask])
          end
        end

        # Define Instance-level atomic methods
        # @note These methods perform the atomic SQL update, then read back the new value
        #   via a separate `pluck` query. There is a small TOCTOU window between the
        #   `update_all` and the `pluck` where another concurrent thread could modify
        #   the same row, causing the in-memory state to diverge from the DB. For
        #   absolute consistency, wrap usage in a transaction or re-read via `reload`.
        singular_col = T.unsafe(column_name.to_s).singularize

        T.unsafe(self).define_method("add_#{singular_col}!") do |*values|
          T.unsafe(self).class.transaction do
            T.unsafe(self).class.public_send("add_#{column_name}!", *T.unsafe(values), records: T.unsafe(self).id)
            new_db_value = T.unsafe(self).class.where(id: T.unsafe(self).id).lock(true).pluck(column_name.to_sym).first || 0
            raw_values = T.unsafe(self).instance_variable_get(:@_bitwise_raw_values)
            unless raw_values
              raw_values = {}
              T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, raw_values)
            end
            raw_values[column_name.to_sym] = new_db_value

            casted = T.unsafe(self).class.attribute_types[column_name.to_s].deserialize(new_db_value)
            T.unsafe(self).write_attribute(column_name, casted)
            T.unsafe(self).clear_attribute_changes([column_name.to_s]) if T.unsafe(self).respond_to?(:clear_attribute_changes)
          end
        end

        T.unsafe(self).define_method("add_#{column_name}!") do |*values|
          T.unsafe(self).send("add_#{singular_col}!", *T.unsafe(values))
        end

        T.unsafe(self).define_method("remove_#{singular_col}!") do |*values|
          T.unsafe(self).class.transaction do
            T.unsafe(self).class.public_send("remove_#{column_name}!", *T.unsafe(values), records: T.unsafe(self).id)
            new_db_value = T.unsafe(self).class.where(id: T.unsafe(self).id).lock(true).pluck(column_name.to_sym).first || 0
            raw_values = T.unsafe(self).instance_variable_get(:@_bitwise_raw_values)
            unless raw_values
              raw_values = {}
              T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, raw_values)
            end
            raw_values[column_name.to_sym] = new_db_value

            casted = T.unsafe(self).class.attribute_types[column_name.to_s].deserialize(new_db_value)
            T.unsafe(self).write_attribute(column_name, casted)
            T.unsafe(self).clear_attribute_changes([column_name.to_s]) if T.unsafe(self).respond_to?(:clear_attribute_changes)
          end
        end

        T.unsafe(self).define_method("remove_#{column_name}!") do |*values|
          T.unsafe(self).send("remove_#{singular_col}!", *T.unsafe(values))
        end

        # Define Scopes
        # @note `with_` and `with_any_` silently drop unrecognized values, returning
        #   `where('1=0')` (empty) only if ALL values are invalid. `with_exact_` returns
        #   `where('1=0')` if ANY value is invalid (strict validation). `without_` drops
        #   unrecognized values and returns `all` if none are valid.
        T.unsafe(self).scope "with_#{column_name}", Kernel.lambda { |*values|
          if values.empty?
            T.unsafe(self).connection.quote_column_name(column_name)
            return T.unsafe(self).all
          end

          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          quoted_col = T.unsafe(self).connection.quote_column_name(column_name)
          if cleaned.include?(0) || cleaned.include?('0') || cleaned.empty?
            return T.unsafe(self).where("#{quoted_col} = 0")
          end

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }
          return T.unsafe(self).where('1=0') if valid.empty?

          mask = valid.reduce(0) { |m, v| m | (1 << normalized_mapping[v]) }
          T.unsafe(self).where("#{quoted_col} & ? = ?", mask, mask)
        }

        T.unsafe(self).scope "with_any_#{column_name}", Kernel.lambda { |*values|
          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          quoted_col = T.unsafe(self).connection.quote_column_name(column_name)
          return T.unsafe(self).all if cleaned.empty?

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }
          return T.unsafe(self).where('1=0') if valid.empty?

          mask = valid.reduce(0) { |m, v| m | (1 << normalized_mapping[v]) }
          T.unsafe(self).where("#{quoted_col} & ? > 0", mask)
        }

        T.unsafe(self).scope "with_exact_#{column_name}", Kernel.lambda { |*values|
          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          quoted_col = T.unsafe(self).connection.quote_column_name(column_name)

          return T.unsafe(self).where("#{quoted_col} = 0") if cleaned.empty?

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }

          return T.unsafe(self).where('1=0') if valid.size < cleaned.size

          mask = valid.reduce(0) { |m, v| m | (1 << normalized_mapping[v]) }
          T.unsafe(self).where("#{quoted_col} = ?", mask)
        }

        T.unsafe(self).scope "without_#{column_name}", Kernel.lambda { |*values|
          cleaned = values.flatten.reject { |v| v.nil? || v == '' }
          quoted_col = T.unsafe(self).connection.quote_column_name(column_name)
          return T.unsafe(self).all if cleaned.empty?

          valid = cleaned.select { |v| mapping_strings.include?(v.to_s) }.map { |v| v.to_s.to_sym }
          return T.unsafe(self).all if valid.empty?

          mask = valid.reduce(0) { |m, v| m | (1 << normalized_mapping[v]) }
          T.unsafe(self).where("#{quoted_col} & ? = 0", mask)
        }

        # Define schema helper class method
        T.unsafe(self).singleton_class.class_eval do
          T.unsafe(self).define_method(:bitwise_schema) do |col|
            T.unsafe(self).bitwise_definitions.dig(col.to_sym, :mapping)
          end
        end

        # Register callbacks (guarded to prevent duplicate registration when
        # multiple bitwise columns are defined on the same model)
        T.unsafe(self).class_eval do
          any_ancestor_registered = T.unsafe(self).ancestors.any? do |ancestor|
            ancestor.instance_variable_defined?(:@_bitwise_callbacks_registered) &&
              ancestor.instance_variable_get(:@_bitwise_callbacks_registered)
          end
          unless any_ancestor_registered
            T.unsafe(self).instance_variable_set(:@_bitwise_callbacks_registered, true)

            T.unsafe(self).after_initialize :_validate_bitwise_column_type_and_bounds
            T.unsafe(self).after_save :_reset_bitwise_raw_value_caches

            T.unsafe(self).define_method(:clear_bitwise_raw_values_cache!) do
              T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, {})
            end

            T.unsafe(self).define_method(:reload) do |*args|
              T.unsafe(self).clear_bitwise_raw_values_cache!
              super(*args)
            end

            T.unsafe(self).define_method(:_validate_bitwise_column_type_and_bounds) do
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

            T.unsafe(self).define_method(:_reset_bitwise_raw_value_caches) do
              T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, {})
            end

            T.unsafe(self).define_method(:initialize_dup) do |other|
              super(other)
              T.unsafe(self).instance_variable_set(:@_bitwise_raw_values, {})
            end
          end
        end
        nil
      end

      # Automatically extends the base class with bitwise definitions attribute.
      # @param base [T::Module[T.anything]] The class extending this module.
      # @return [void]
      sig { params(base: T::Module[T.anything]).void }
      def self.extended(base)
        T.unsafe(base).class_attribute :bitwise_definitions, default: {}
      end
    end
  end
end

T.unsafe(ActiveSupport).on_load(:active_record) do
  extend ActiveRecord::Bitwise::Model
  ActiveRecord::Relation.prepend(ActiveRecord::Bitwise::RelationExtension)
  ActiveRecord::QueryMethods::WhereChain.prepend(ActiveRecord::Bitwise::WhereChainExtension)
end
