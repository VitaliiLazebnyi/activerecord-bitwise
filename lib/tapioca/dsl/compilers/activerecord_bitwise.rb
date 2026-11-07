# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise'
require 'sorbet-runtime'

begin
  require 'tapioca/dsl'
rescue LoadError
  # Namespace for Tapioca integration.
  module Tapioca
    # Namespace for Tapioca DSL.
    module Dsl
      # Stand-in for Tapioca's compiler base class, installed as +Tapioca::Dsl::Compiler+ where Tapioca is not
      # loaded (the specs run without it).
      class CompilerStandIn
        extend T::Sig

        # Stub for type member definition.
        # @param args [Array<Object>]
        # @return [Array<Object>]
        sig { params(args: Object).returns(T::Array[Object]) }
        def self.type_member(*args)
          args
        end

        # Returns descendants of a class.
        # @param klass [Class]
        # @return [Array<Class>]
        sig { params(klass: T::Class[T.anything]).returns(T::Array[T::Class[T.anything]]) }
        def self.descendants_of(klass)
          ObjectSpace.each_object(Class).select { |candidate| candidate < klass }
        end

        # Stub for gathering constants.
        # @return [Array<Module>]
        sig { returns(T::Enumerable[T::Module[T.anything]]) }
        def self.gather_constants
          []
        end

        # The model constant being compiled.
        # @return [Module]
        sig { returns(T::Module[T.anything]) }
        attr_reader :constant

        # The root node of the generated RBI tree.
        # @return [Object, nil]
        sig { returns(T.nilable(Object)) }
        attr_reader :root

        # Initializes a new compiler.
        # @param constant [Module]
        sig { params(constant: T::Module[T.anything]).void }
        def initialize(constant)
          @constant = constant
          @root = T.let(nil, T.nilable(Object))
        end

        # Stub for decorating model RBI.
        # @return [void]
        sig { void }
        def decorate; end

        # Stub for creating a method parameter: describes it as [kind, name, type].
        # @param name [String]
        # @param type [String]
        # @return [Array<Object>]
        sig { params(name: String, type: String).returns(T::Array[Object]) }
        def create_param(name, type:)
          [__callee__, name, type]
        end
        alias create_rest_param create_param
        alias create_kw_param create_param
      end

      const_set(:Compiler, CompilerStandIn)
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
        public_constant :ConstantType

        # A parameter of a generated method: its kind (:param, :rest or :keyword), name and Sorbet type.
        class Param < T::Struct
          extend T::Sig

          const :kind, Symbol
          const :name, String
          const :type, String

          # The RBI parameter that stands for this one.
          # @param builders [Hash{Symbol => Method}] The compiler's parameter builders, by kind.
          # @return [Object]
          sig { params(builders: T::Hash[Symbol, Method]).returns(Object) }
          def build(builders)
            builders.fetch(kind).call(name, type: type)
          end
        end

        # A method the `bitwise` macro generates, as the RBI declares it.
        class Signature < T::Struct
          extend T::Sig

          const :name, String
          const :return_type, String
          const :parameters, T::Array[Param], default: []
          const :class_method, T::Boolean, default: false

          # Declares the method.
          # @param creator [Method] The +create_method+ of the model's RBI scope.
          # @param builders [Hash{Symbol => Method}] The compiler's parameter builders, by kind.
          # @return [void]
          sig { params(creator: Method, builders: T::Hash[Symbol, Method]).void }
          def declare(creator, builders)
            creator.call(name, parameters: parameters.map { |param| param.build(builders) },
                               return_type: return_type, class_method: class_method)
          end
        end

        # The signatures of the methods the `bitwise` macro generates.
        module Signatures
          extend T::Sig

          # The Sorbet type of the flag names users pass in.
          NAME = 'T.any(Symbol, String)'
          public_constant :NAME

          # The Sorbet type of a flag array.
          FLAGS = 'T::Array[T.any(Symbol, String)]'
          public_constant :FLAGS

          # The splat of flag names that most generated methods take.
          VALUES = Param.new(kind: :rest, name: 'values', type: NAME)
          public_constant :VALUES

          # The signature of `bitwise_schema`.
          # @return [Signature]
          sig { returns(Signature) }
          def self.schema
            Signature.new(name: 'bitwise_schema', return_type: 'T.nilable(T::Hash[Symbol, Integer])',
                          parameters: [Param.new(kind: :param, name: 'col', type: NAME)], class_method: true)
          end

          # The signatures of all methods generated for one column.
          # @param declaration [ActiveRecord::Bitwise::Declaration]
          # @return [Array<Signature>]
          sig { params(declaration: ActiveRecord::Bitwise::Declaration).returns(T::Array[Signature]) }
          def self.column(declaration)
            column = declaration.column_name.to_s
            [*accessors(column), *flags(declaration), *instance_atomic(column), *class_atomic(column), *scopes(column)]
          end

          # The getter and setter of the column.
          # @param column [String] The column name.
          # @return [Array<Signature>]
          sig { params(column: String).returns(T::Array[Signature]) }
          def self.accessors(column)
            [Signature.new(name: column, return_type: FLAGS),
             Signature.new(name: "#{column}=", return_type: FLAGS,
                           parameters: [Param.new(kind: :param, name: 'val', type: FLAGS)])]
          end
          private_class_method :accessors

          # The `flag?`, `flag=` and `flag!` methods of every flag.
          # @param declaration [ActiveRecord::Bitwise::Declaration]
          # @return [Array<Signature>]
          sig { params(declaration: ActiveRecord::Bitwise::Declaration).returns(T::Array[Signature]) }
          def self.flags(declaration)
            declaration.flags.keys.flat_map do |name|
              [Signature.new(name: "#{name}?", return_type: 'T::Boolean'),
               Signature.new(name: "#{name}=", return_type: 'T::Boolean',
                             parameters: [Param.new(kind: :param, name: 'val', type: 'T::Boolean')]),
               Signature.new(name: "#{name}!", return_type: 'TrueClass')]
            end
          end
          private_class_method :flags

          # The instance-level atomic methods.
          # @param column [String] The column name.
          # @return [Array<Signature>]
          sig { params(column: String).returns(T::Array[Signature]) }
          def self.instance_atomic(column)
            singular = column.singularize
            names = %w[add remove].product([singular, column])
            names.map! do |operation, name|
              Signature.new(name: "#{operation}_#{name}!", return_type: 'void', parameters: [VALUES])
            end
          end
          private_class_method :instance_atomic

          # The class-level atomic methods.
          # @param column [String] The column name.
          # @return [Array<Signature>]
          sig { params(column: String).returns(T::Array[Signature]) }
          def self.class_atomic(column)
            records = Param.new(kind: :keyword, name: 'records', type: 'T.untyped')
            %w[add remove].map do |operation|
              Signature.new(name: "#{operation}_#{column}!", return_type: 'void', parameters: [VALUES, records],
                            class_method: true)
            end
          end
          private_class_method :class_atomic

          # The four scopes of the column.
          # @param column [String] The column name.
          # @return [Array<Signature>]
          sig { params(column: String).returns(T::Array[Signature]) }
          def self.scopes(column)
            %w[with_ with_any_ with_exact_ without_].map do |prefix|
              Signature.new(name: "#{prefix}#{column}", return_type: 'ActiveRecord::Relation', parameters: [VALUES],
                            class_method: true)
            end
          end
          private_class_method :scopes
        end

        # Models that declare at least one bitwise column.
        # @return [Array<Class>]
        sig { override.returns(T::Enumerable[T::Module[T.anything]]) }
        def self.gather_constants
          descendants_of(ActiveRecord::Base).select do |klass|
            ActiveRecord::Bitwise::Definitions.bitwise?(klass) && klass.bitwise_definitions.any?
          end
        end

        # Declares the methods the `bitwise` macro generates for the model.
        # @return [void]
        sig { override.void }
        def decorate
          declare([Signatures.schema])
          constant.bitwise_definitions.each do |column, definition|
            declare(Signatures.column(ActiveRecord::Bitwise::Declaration.from(column, definition)))
          end
        end

        private

        # Declares +signatures+ on the model.
        # @param signatures [Array<Signature>]
        # @return [void]
        sig { params(signatures: T::Array[Signature]).void }
        def declare(signatures)
          root.create_path(constant) { |model| emit(model.method(:create_method), signatures) }
        end

        # Declares +signatures+ with +creator+.
        # @param creator [Method] The +create_method+ of the model's RBI scope.
        # @param signatures [Array<Signature>]
        # @return [void]
        sig { params(creator: Method, signatures: T::Array[Signature]).void }
        def emit(creator, signatures)
          builders = { param: method(:create_param), rest: method(:create_rest_param),
                       keyword: method(:create_kw_param) }
          signatures.each { |signature| signature.declare(creator, builders) }
        end
      end
    end
  end
end
