# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/collisions'
require 'active_record/bitwise/declaration'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/instance_methods'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/mapping'
require 'active_record/bitwise/model/generated_methods'
require 'active_record/bitwise/model/scopes'
require 'active_record/bitwise/options'
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
      extend T::Helpers

      requires_ancestor { T.class_of(ActiveRecord::Base) }

      include GeneratedMethods
      include Scopes

      # Defines bitwise attributes, getters, setters, scopes, and helper methods.
      # @param column_name [Symbol, String] The database column name.
      # @param mapping [Hash{Symbol, String => Integer, String}, Array<Symbol, String>] The enum/boolean value
      #   mapping. Hash values are bit *positions* (`1 << position`), not masks.
      # @param options [Hash] The options +default:+ (an Array of flags that must be present in the mapping),
      #   +prefix:+ and +suffix:+ (a name, or +true+ for the singular column name) for the method names.
      # @raise [ArgumentError] For an unknown option.
      # @raise [ConfigurationError] On invalid mappings, defaults, or method collisions.
      # @return [void]
      sig do
        params(
          column_name: Types::Name,
          mapping: T.any(T::Hash[Types::Name, T.any(Integer, String)], Types::Flags),
          options: Options::Value
        ).void
      end
      def bitwise(column_name, mapping, **options)
        layout = Layout.new(column_name, Mapping.normalize(column_name, mapping))
        declaration = Declaration.new(layout, Options.parse(options))
        _bitwise_declare(declaration)
        _bitwise_define_methods(declaration)
        nil
      end

      # Returns a copy of the mapping schema for the specified bitwise column.
      # @param col [Symbol, String] The column name.
      # @return [Hash{Symbol => Integer}, nil]
      sig { params(col: Types::Name).returns(T.nilable(Types::Positions)) }
      def bitwise_schema(col)
        bitwise_definitions.dig(col.to_sym, :mapping)&.dup
      end

      # Gives every subclass its own deep copy of the bitwise definitions so a
      # subclass (or a spec) mutating its configuration can never leak state into
      # the parent class or into sibling subclasses.
      # @param subclass [Class] The new subclass.
      # @return [void]
      sig { params(subclass: T.class_of(ActiveRecord::Base)).void }
      def inherited(subclass)
        super
        definitions = bitwise_definitions
        return if definitions.blank?

        subclass.bitwise_definitions = definitions.transform_values do |config|
          config.merge(mapping: config[:mapping].dup)
        end
      end

      # Automatically extends the base class with the bitwise definitions attribute.
      # Guarded so extending a subclass never wipes definitions inherited from a parent.
      # @param base [Class] The class extending this module.
      # @return [void]
      sig { params(base: T::Class[T.anything]).void }
      def self.extended(base)
        return if base.singleton_class.method_defined?(:bitwise_definitions)

        base.class_attribute :bitwise_definitions, default: {}
      end

      private

      # Checks the generated method names, records the definition and registers the attribute type.
      # @param declaration [ActiveRecord::Bitwise::Declaration]
      # @raise [ArgumentError] On a collision with core ActiveRecord::Base methods.
      # @raise [ConfigurationError] On a collision with another bitwise column or a database column.
      # @return [void]
      sig { params(declaration: Declaration).void }
      def _bitwise_declare(declaration)
        generated = Collisions.for(bitwise_definitions, _bitwise_attribute_names, declaration).generated_methods
        self.bitwise_definitions = bitwise_definitions.merge(declaration.column => declaration.definition(generated))
        attribute declaration.column_name, declaration.type, default: declaration.defaults
      end

      # Defines the getter, flag methods, atomic methods and scopes of a declared column, and registers the
      # instance behavior.
      # @param declaration [ActiveRecord::Bitwise::Declaration]
      # @return [void]
      sig { params(declaration: Declaration).void }
      def _bitwise_define_methods(declaration)
        _bitwise_define_getter(declaration)
        _bitwise_define_flag_methods(declaration)
        _bitwise_define_atomic_methods(declaration)
        _bitwise_define_scopes(declaration)
        _bitwise_install_instance_methods
      end

      # The column names of the model's table (none when the table cannot be inspected yet).
      # @return [Array<String>]
      sig { returns(T::Array[String]) }
      def _bitwise_attribute_names
        table_exists? ? column_names : []
      rescue StandardError
        []
      end

      # Registers instance behavior and callbacks exactly once per inheritance tree.
      # @return [void]
      sig { void }
      def _bitwise_install_instance_methods
        return if self <= InstanceMethods

        include InstanceMethods

        after_initialize :_validate_bitwise_column_type_and_bounds
        after_save :_reset_bitwise_raw_value_caches
      end
    end
  end
end
