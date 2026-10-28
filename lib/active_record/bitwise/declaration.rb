# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/errors'
require 'active_record/bitwise/flag'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/options'
require 'active_record/bitwise/type'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # One `bitwise` declaration: the column, its flags and options, and the names of the methods generated
    # for them.
    class Declaration
      extend T::Sig

      # What the `bitwise` macro records per declared column (readable through +bitwise_definitions+).
      Definition = T.type_alias do
        {
          mapping: Types::Positions,
          default: Types::Flags,
          prefix: Options::Affix,
          suffix: Options::Affix,
          validated: T::Boolean,
          generated_methods: T::Array[String]
        }
      end
      public_constant :Definition

      # The flags of the column.
      # @return [ActiveRecord::Bitwise::Layout]
      sig { returns(Layout) }
      attr_reader :layout

      # The default values for new records.
      # @return [Array<Symbol, String>]
      sig { returns(Types::Flags) }
      attr_reader :defaults

      # Rebuilds the declaration of a column from the record `bitwise_definitions` keeps for it.
      # @param column [Symbol] The column.
      # @param definition [Hash{Symbol => Object}] What the macro recorded for the column.
      # @return [ActiveRecord::Bitwise::Declaration]
      sig { params(column: Symbol, definition: Definition).returns(Declaration) }
      def self.from(column, definition)
        options = Options.new(default: definition.fetch(:default), prefix: definition.fetch(:prefix),
                              suffix: definition.fetch(:suffix))
        new(Layout.new(column, definition.fetch(:mapping)), options)
      end

      # @param layout [ActiveRecord::Bitwise::Layout] The flags of the column.
      # @param options [ActiveRecord::Bitwise::Options] The options of the macro.
      # @raise [ConfigurationError] When a default is not in the mapping.
      sig { params(layout: Layout, options: Options).void }
      def initialize(layout, options)
        @layout = layout
        @options = options
        @defaults = T.let(valid_defaults(Array(options.default)), Types::Flags)
      end

      # The database column name, as it was declared.
      # @return [Symbol, String]
      sig { returns(Types::Name) }
      def column_name
        layout.column_name
      end

      # The column name as a Symbol.
      # @return [Symbol]
      sig { returns(Symbol) }
      def column
        column_name.to_sym
      end

      # The flags, by the name of the method group generated for each.
      # @return [Hash{String => ActiveRecord::Bitwise::Flag}]
      sig { returns(T::Hash[String, Flag]) }
      def flags
        layout.mapping.to_h { |key, _position| [method_name(key), Flag.new(column_name, key)] }
      end

      # The attribute type of the column.
      # @return [ActiveRecord::Bitwise::Type]
      sig { returns(Type) }
      def type
        Type.new(column_name, layout.mapping, defaults)
      end

      # The name of the method group generated for the flag +key+.
      # @param key [Symbol] A flag name.
      # @return [String]
      sig { params(key: Symbol).returns(String) }
      def method_name(key)
        "#{affix(@options.prefix, '%s_')}#{key}#{affix(@options.suffix, '_%s')}"
      end

      # The record `bitwise_definitions` keeps for the column.
      # @param generated [Array<String>] The names of the generated methods.
      # @return [Hash{Symbol => Object}]
      sig { params(generated: T::Array[String]).returns(Definition) }
      def definition(generated)
        {
          mapping: layout.mapping, default: defaults, prefix: @options.prefix, suffix: @options.suffix,
          validated: false, generated_methods: generated
        }
      end

      private

      # Rejects defaults that are not flags of the column.
      # @param defaults [Array<Symbol, String>] The declared default values.
      # @raise [ConfigurationError] When a default is not in the mapping.
      # @return [Array<Symbol, String>] +defaults+.
      sig { params(defaults: Types::Flags).returns(Types::Flags) }
      def valid_defaults(defaults)
        invalid = defaults.reject { |flag| layout.mapped?(flag) }
        return defaults if invalid.empty?

        raise ConfigurationError, "Bitwise column #{column_name} default contains values not present " \
                                  "in the mapping: #{invalid.map(&:to_s).inspect}"
      end

      # The affix a +prefix:+/+suffix:+ option stands for.
      # @param option [Symbol, String, Boolean, nil] The option.
      # @param template [String] How the name is joined to the flag name.
      # @return [String, nil] The formatted name, or nil without an affix.
      sig { params(option: Options::Affix, template: String).returns(T.nilable(String)) }
      def affix(option, template)
        return unless option

        format(template, (option in true) ? column_name.to_s.singularize : option)
      end
    end
  end
end
