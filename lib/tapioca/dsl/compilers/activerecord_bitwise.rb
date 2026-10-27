# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise'

begin
  require 'tapioca/dsl'
rescue LoadError
  require 'tapioca/dsl/compiler_stub'
end

# Namespace for Tapioca integration.
module Tapioca
  # Namespace for Tapioca DSL.
  module Dsl
    # Namespace for specific Tapioca DSL compilers.
    module Compilers
      # Tapioca DSL Compiler for Sorbet static analysis of ActiveRecord::Bitwise attributes and scopes.
      class ActiveRecordBitwise < Compiler
        extend T::Sig

        # The fixed constant type that this compiler is responsible for.
        ConstantType = type_member { { fixed: T.class_of(ActiveRecord::Base) } }
        public_constant :ConstantType

        # Sorbet type of one flag name.
        FLAG_NAME = 'T.any(Symbol, String)'
        private_constant :FLAG_NAME

        # Sorbet type of a list of flag names.
        FLAG_LIST = 'T::Array[T.any(Symbol, String)]'
        private_constant :FLAG_LIST

        # Models that declare at least one bitwise column.
        # @return [T::Enumerable[T::Module[T.anything]]]
        sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
        def self.gather_constants
          descendants_of(ActiveRecord::Base).select do |klass|
            klass.respond_to?(:bitwise_definitions) && T.unsafe(klass).bitwise_definitions.any?
          end
        end

        # Generates the RBI for the schema reader and every bitwise column.
        # @return [void]
        sig { override.void }
        def decorate
          T.unsafe(root).create_path(constant) { |model| decorate_schema(model) }
          T.unsafe(constant).bitwise_definitions.each { |column_name, config| decorate_path(column_name, config) }
        end

        private

        # Generates everything one bitwise column adds to the model, inside the model's RBI path.
        # @param column_name [Symbol]
        # @param config [T::Hash[Symbol, T.untyped]] The column's definition.
        # @return [void]
        sig { params(column_name: Symbol, config: T::Hash[Symbol, T.untyped]).void }
        def decorate_path(column_name, config)
          T.unsafe(root).create_path(constant) { |model| decorate_column(model, column_name, config) }
        end

        # Generates `bitwise_schema`.
        # @param model [T.untyped] The RBI class node.
        # @return [void]
        sig { params(model: T.untyped).void }
        def decorate_schema(model)
          model.create_method('bitwise_schema',
                              parameters: [create_param('col', type: FLAG_NAME)],
                              return_type: 'T.nilable(T::Hash[Symbol, Integer])',
                              class_method: true)
        end

        # Generates everything one bitwise column adds to the model.
        # @param model [T.untyped] The RBI class node.
        # @param column_name [Symbol]
        # @param config [T::Hash[Symbol, T.untyped]] The column's definition.
        # @return [void]
        sig { params(model: T.untyped, column_name: Symbol, config: T::Hash[Symbol, T.untyped]).void }
        def decorate_column(model, column_name, config)
          decorate_accessors(model, column_name)
          decorate_flags(model, column_name, config)
          decorate_atomics(model, column_name)
          decorate_scopes(model, column_name)
        end

        # Generates the column reader and writer.
        # @param model [T.untyped]
        # @param column_name [Symbol]
        # @return [void]
        sig { params(model: T.untyped, column_name: Symbol).void }
        def decorate_accessors(model, column_name)
          model.create_method(column_name.to_s, return_type: FLAG_LIST)
          model.create_method("#{column_name}=", parameters: [create_param('val', type: FLAG_LIST)],
                                                 return_type: FLAG_LIST)
        end

        # Generates `flag?`, `flag=` and `flag!` for every mapped flag.
        # @param model [T.untyped]
        # @param column_name [Symbol]
        # @param config [T::Hash[Symbol, T.untyped]]
        # @return [void]
        sig { params(model: T.untyped, column_name: Symbol, config: T::Hash[Symbol, T.untyped]).void }
        def decorate_flags(model, column_name, config)
          prefix = ActiveRecord::Bitwise::Model::Mapping.prefix(column_name, config[:prefix])
          suffix = ActiveRecord::Bitwise::Model::Mapping.suffix(column_name, config[:suffix])
          config[:mapping].each_key do |key|
            name = "#{prefix}#{key}#{suffix}"
            model.create_method("#{name}?", return_type: 'T::Boolean')
            model.create_method("#{name}=", parameters: [create_param('val', type: 'T::Boolean')], return_type: 'T::Boolean')
            model.create_method("#{name}!", return_type: 'TrueClass')
          end
        end

        # Generates the instance-level and class-level atomic add/remove methods.
        # @param model [T.untyped]
        # @param column_name [Symbol]
        # @return [void]
        sig { params(model: T.untyped, column_name: Symbol).void }
        def decorate_atomics(model, column_name)
          singular = T.unsafe(column_name.to_s).singularize
          %w[add remove].each do |operation|
            model.create_method("#{operation}_#{singular}!", parameters: [flag_values], return_type: 'void')
            model.create_method("#{operation}_#{column_name}!", parameters: [flag_values], return_type: 'void')
            model.create_method("#{operation}_#{column_name}!", parameters: [flag_values, records_keyword],
                                                                return_type: 'void', class_method: true)
          end
        end

        # Generates the four query scopes.
        # @param model [T.untyped]
        # @param column_name [Symbol]
        # @return [void]
        sig { params(model: T.untyped, column_name: Symbol).void }
        def decorate_scopes(model, column_name)
          ["with_#{column_name}", "with_any_#{column_name}", "with_exact_#{column_name}",
           "without_#{column_name}"].each do |scope|
            model.create_method(scope, parameters: [flag_values], return_type: 'ActiveRecord::Relation',
                                       class_method: true)
          end
        end

        # The `*values` parameter shared by the atomic methods and scopes.
        # @return [T.untyped]
        sig { returns(T.untyped) }
        def flag_values
          create_rest_param('values', type: FLAG_NAME)
        end

        # The `records:` keyword parameter of the class-level atomic methods.
        # @return [T.untyped]
        sig { returns(T.untyped) }
        def records_keyword
          create_kw_param('records', type: 'T.untyped')
        end
      end
    end
  end
end
