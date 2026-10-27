# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

# Namespace for Tapioca integration.
module Tapioca
  # Namespace for Tapioca DSL.
  module Dsl
    # Stand-in for Tapioca's compiler base class, used only when Tapioca is not
    # installed so the compiler file can still be loaded (and tested) without it.
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

      # Stub for the type member declaration. Sorbet's runtime signature verification requires the block
      # argument to be named (matching `blk` in the sig) and raises if an anonymous `&` is used.
      # @param _args [T.untyped]
      # @return [T.untyped]
      sig { params(_args: T.untyped, blk: T.nilable(T.proc.returns(T.untyped))).returns(T.untyped) }
      def self.type_member(*_args, &blk); end # rubocop:disable Naming/BlockForwarding

      # Returns descendants of a class.
      # @param klass [T.untyped]
      # @return [T::Array[T.untyped]]
      sig { params(klass: T.untyped).returns(T::Array[T.untyped]) }
      def self.descendants_of(klass)
        ObjectSpace.each_object(Class).select { |candidate| candidate < klass }
      end

      # Stub for gathering constants.
      # @return [T.untyped]
      sig { returns(T.untyped) }
      def self.gather_constants; end

      # Initializes a new compiler.
      # @param constant [T.untyped]
      sig { params(constant: T.untyped).void }
      def initialize(constant)
        @constant = constant
        @root = T.let(nil, T.untyped)
      end

      # Stub for decorating model RBI.
      # @return [void]
      sig { void }
      def decorate; end

      # Stub for creating a method parameter.
      # @param _name [String]
      # @param type [String]
      # @return [T.untyped]
      sig { params(_name: String, type: String).returns(T.untyped) }
      def create_param(_name, type:); end

      # Stub for creating a method rest parameter.
      # @param _name [String]
      # @param type [String]
      # @return [T.untyped]
      sig { params(_name: String, type: String).returns(T.untyped) }
      def create_rest_param(_name, type:); end

      # Stub for creating a method keyword parameter.
      # @param _name [String]
      # @param type [String]
      # @return [T.untyped]
      sig { params(_name: String, type: String).returns(T.untyped) }
      def create_kw_param(_name, type:); end
    end
  end
end
