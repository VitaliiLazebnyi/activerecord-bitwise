# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/instance_methods'
require 'active_record/bitwise/model/collisions'
require 'active_record/bitwise/model/definers/atomic_methods'
require 'active_record/bitwise/model/definers/flag_methods'
require 'active_record/bitwise/model/definers/getter'
require 'active_record/bitwise/model/definers/scopes'
require 'active_record/bitwise/model/mapping'
require 'active_record/bitwise/type'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
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
      # @param mapping [T.any(T::Hash[T.any(Symbol, String), T.any(Integer, String)], T::Array[T.any(Symbol, String)])]
      #   The enum/boolean value mapping. Hash values are bit *positions* (`1 << position`), not masks.
      # @param default [T.nilable(T::Array[T.any(Symbol, String)])] Optional default values (must be in the mapping).
      # @param prefix [T.nilable(T.any(Symbol, String, T::Boolean))] Optional prefix for method names.
      # @param suffix [T.nilable(T.any(Symbol, String, T::Boolean))] Optional suffix for method names.
      # @raise [ConfigurationError] On invalid mappings, defaults, or method collisions.
      # @return [void]
      sig do
        params(
          column_name: Types::Name,
          mapping: T.any(T::Hash[Types::Name, T.any(Integer, String)], Types::Flags),
          default: T.nilable(Types::Flags),
          prefix: T.nilable(T.any(Symbol, String, T::Boolean)),
          suffix: T.nilable(T.any(Symbol, String, T::Boolean))
        ).void
      end
      def bitwise(column_name, mapping, default: nil, prefix: nil, suffix: nil)
        normalized = Mapping.normalize(column_name, mapping)
        defaults = _bitwise_validated_defaults(column_name, normalized, default)
        _bitwise_declare(column_name, normalized, defaults, { prefix: prefix, suffix: suffix })
        _bitwise_install_instance_methods
        nil
      end

      # Returns a copy of the mapping schema for the specified bitwise column.
      # @param col [T.any(Symbol, String)] The column name.
      # @return [T.nilable(T::Hash[Symbol, Integer])]
      sig { params(col: Types::Name).returns(T.nilable(Types::Positions)) }
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
          config.dup.tap { |copied| copied[:mapping] = config[:mapping].dup }
        end
      end

      # Automatically extends the base class with the bitwise definitions attribute.
      # Guarded so extending a subclass never wipes definitions inherited from a parent.
      # @param base [T::Module[T.anything]] The class extending this module.
      # @return [void]
      sig { params(base: T::Module[T.anything]).void }
      def self.extended(base)
        return if T.unsafe(base).respond_to?(:bitwise_definitions)

        T.unsafe(base).class_attribute :bitwise_definitions, default: {}
      end

      private

      # Validates that every default is part of the mapping.
      # @param column_name [T.any(Symbol, String)]
      # @param mapping [T::Hash[Symbol, Integer]]
      # @param default [T.nilable(T::Array[T.any(Symbol, String)])]
      # @raise [ConfigurationError] When a default is not in the mapping.
      # @return [T::Array[T.any(Symbol, String)]] The defaults (empty when none were given).
      sig do
        params(column_name: Types::Name, mapping: Types::Positions,
               default: T.nilable(Types::Flags)).returns(Types::Flags)
      end
      def _bitwise_validated_defaults(column_name, mapping, default)
        defaults = Kernel.Array(default)
        names = mapping.keys.map(&:to_s)
        invalid = defaults.reject { |value| names.include?(value.to_s) }
        return defaults if invalid.empty?

        Kernel.raise ConfigurationError,
                     "Bitwise column #{column_name} default contains values not present in the mapping: " \
                     "#{invalid.map(&:to_s).inspect}"
      end

      # Checks for collisions, records the configuration and defines every generated method.
      # @param column_name [T.any(Symbol, String)]
      # @param mapping [T::Hash[Symbol, Integer]]
      # @param defaults [T::Array[T.any(Symbol, String)]]
      # @param affixes [T::Hash[Symbol, T.untyped]] The +prefix+ and +suffix+ options as given.
      # @return [void]
      sig do
        params(column_name: Types::Name, mapping: Types::Positions, defaults: Types::Flags,
               affixes: T::Hash[Symbol, T.untyped]).void
      end
      def _bitwise_declare(column_name, mapping, defaults, affixes)
        prefix = Mapping.prefix(column_name, affixes[:prefix])
        suffix = Mapping.suffix(column_name, affixes[:suffix])
        generated = Collisions.check!(self, column_name, mapping, prefix, suffix)
        _bitwise_register(column_name, mapping, defaults, affixes.merge(generated_methods: generated))
        _bitwise_define_accessors(column_name, mapping, prefix, suffix)
      end

      # Records the column's configuration in a fresh copy of the class-level definitions.
      # @param column_name [T.any(Symbol, String)]
      # @param mapping [T::Hash[Symbol, Integer]]
      # @param defaults [T::Array[T.any(Symbol, String)]]
      # @param extras [T::Hash[Symbol, T.untyped]] Prefix, suffix and generated method names.
      # @return [void]
      sig do
        params(column_name: Types::Name, mapping: Types::Positions,
               defaults: Types::Flags, extras: T::Hash[Symbol, T.untyped]).void
      end
      def _bitwise_register(column_name, mapping, defaults, extras)
        T.unsafe(self).bitwise_definitions = T.unsafe(self).bitwise_definitions.dup
        T.unsafe(self).bitwise_definitions[column_name.to_sym] =
          { mapping: mapping, default: defaults, validated: false, **extras }
        T.unsafe(self).attribute column_name, Type.new(column_name, mapping, defaults), default: defaults
      end

      # Defines the getter, flag methods, atomic methods and scopes.
      # @param column_name [T.any(Symbol, String)]
      # @param mapping [T::Hash[Symbol, Integer]]
      # @param prefix [String]
      # @param suffix [String]
      # @return [void]
      sig do
        params(column_name: Types::Name, mapping: Types::Positions, prefix: String,
               suffix: String).void
      end
      def _bitwise_define_accessors(column_name, mapping, prefix, suffix)
        Definers::Getter.define(self, column_name)
        Definers::FlagMethods.define(self, column_name, mapping, prefix, suffix)
        Definers::AtomicMethods.define(self, column_name, mapping)
        Definers::Scopes.define(self, column_name, mapping)
      end

      # Registers instance behavior and callbacks exactly once per inheritance tree.
      # @return [void]
      sig { void }
      def _bitwise_install_instance_methods
        return if T.unsafe(self) <= ActiveRecord::Bitwise::InstanceMethods

        T.unsafe(self).include(ActiveRecord::Bitwise::InstanceMethods)
        T.unsafe(self).after_initialize :_validate_bitwise_column_type_and_bounds
        T.unsafe(self).after_save :_reset_bitwise_raw_value_caches
      end
    end
  end
end
