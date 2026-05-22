# typed: strict
# frozen_string_literal: true

begin
  require 'tapioca/dsl'
rescue LoadError
  # Namespace for Tapioca integration.
  module Tapioca
    # Namespace for Tapioca DSL.
    module Dsl
      # Stub class for Compiler under environments where Tapioca is not loaded.
      class Compiler
        extend T::Sig

        # The model constant being compiled.
        # @return [T.untyped]
        sig { returns(T.untyped) }
        attr_reader :constant

        # The root node of the generated RBI tree.
        # @return [T.untyped]
        sig { returns(T.untyped) }
        attr_reader :root

        # Initializes a new compiler.
        # @param constant [T.untyped]
        sig { params(constant: T.untyped).void }
        def initialize(constant)
          @constant = T.let(constant, T.untyped)
          @root = T.let(nil, T.untyped)
        end

        # Stub for type member definition.
        # @param args [T.untyped]
        # Sorbet's runtime signature verification requires the block argument to be named in the method definition
        # (i.e. matching the `blk` name in `sig { params(blk: ...) }`) and raises `RuntimeError` if anonymous `&` is used.
        # rubocop:disable Naming/BlockForwarding
        sig { params(args: T.untyped, blk: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
        def self.type_member(*args, &blk)
          # Stub for environments without Tapioca
        end
        # rubocop:enable Naming/BlockForwarding

        # Returns descendants of a class.
        # @param klass [T.untyped]
        # @return [T::Array[T.untyped]]
        sig { params(klass: T.untyped).returns(T::Array[T.untyped]) }
        def self.descendants_of(klass)
          ObjectSpace.each_object(Class).select { |c| c < klass }
        end

        # Stub for gathering constants.
        # @return [T.untyped]
        sig { returns(T.untyped) }
        def self.gather_constants
          # Stub for override verification
        end

        # Stub for decorating model RBI.
        # @return [void]
        sig { void }
        def decorate
          # Stub for override verification
        end

        # Stub for creating method parameter.
        # @param name [String]
        # @param type [String]
        sig { params(name: String, type: String).returns(T.untyped) }
        def create_param(name, type:)
          # Stub
        end

        # Stub for creating method rest parameter.
        # @param name [String]
        # @param type [String]
        sig { params(name: String, type: String).returns(T.untyped) }
        def create_rest_param(name, type:)
          # Stub
        end

        # Stub for creating method keyword parameter.
        # @param name [String]
        # @param type [String]
        sig { params(name: String, type: String).returns(T.untyped) }
        def create_kw_param(name, type:)
          # Stub
        end
      end
    end
  end
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

        sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
        def self.gather_constants
          descendants_of(ActiveRecord::Base).select do |klass|
            klass.respond_to?(:bitwise_definitions) && T.unsafe(klass).bitwise_definitions.any?
          end
        end

        sig { override.void }
        def decorate
          T.unsafe(root).create_path(constant) do |model|
            model.create_method('bitwise_schema',
                                parameters: [create_param('col', type: 'T.any(Symbol, String)')],
                                return_type: 'T.nilable(T::Hash[Symbol, Integer])',
                                class_method: true)
          end

          T.unsafe(constant).bitwise_definitions.each do |column_name, config|
            T.unsafe(root).create_path(constant) do |model|
              model.create_method(column_name.to_s, return_type: 'T::Array[T.any(Symbol, String)]')
              model.create_method("#{column_name}=",
                                  parameters: [create_param('val', type: 'T::Array[T.any(Symbol, String)]')], return_type: 'T::Array[T.any(Symbol, String)]')

              prefix = config[:prefix]
              suffix = config[:suffix]
              mapping = config[:mapping]

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

              mapping.each_key do |key|
                method_name = "#{prefix_str}#{key}#{suffix_str}"
                model.create_method("#{method_name}?", return_type: 'T::Boolean')
                model.create_method("#{method_name}=", parameters: [create_param('val', type: 'T::Boolean')],
                                                       return_type: 'T::Boolean')
                model.create_method("#{method_name}!", return_type: 'TrueClass')
              end

              # Instance-level atomic methods
              singular_col = T.unsafe(column_name.to_s).singularize
              model.create_method("add_#{singular_col}!",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'void')
              model.create_method("add_#{column_name}!",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'void')
              model.create_method("remove_#{singular_col}!",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'void')
              model.create_method("remove_#{column_name}!",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'void')

              # Class-level atomic methods
              model.create_method("add_#{column_name}!",
                                  parameters: [
                                    create_rest_param('values', type: 'T.any(Symbol, String)'),
                                    create_kw_param('records', type: 'T.untyped')
                                  ],
                                  return_type: 'void',
                                  class_method: true)
              model.create_method("remove_#{column_name}!",
                                  parameters: [
                                    create_rest_param('values', type: 'T.any(Symbol, String)'),
                                    create_kw_param('records', type: 'T.untyped')
                                  ],
                                  return_type: 'void',
                                  class_method: true)

              # Scopes
              model.create_method("with_#{column_name}",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'ActiveRecord::Relation',
                                  class_method: true)
              model.create_method("with_any_#{column_name}",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'ActiveRecord::Relation',
                                  class_method: true)
              model.create_method("with_exact_#{column_name}",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'ActiveRecord::Relation',
                                  class_method: true)
              model.create_method("without_#{column_name}",
                                  parameters: [create_rest_param('values', type: 'T.any(Symbol, String)')],
                                  return_type: 'ActiveRecord::Relation',
                                  class_method: true)
            end
          end
        end
      end
    end
  end
end
