# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Stands in for Tapioca's RBI tree (the external boundary of the Tapioca DSL compiler):
# it plays both the root and the model scope, and records every method the compiler declares.
class RbiRecorder
  extend T::Sig

  # One declared method: its name, return type and whether it is a class method.
  class Declaration
    extend T::Sig

    # @return [Array(String, String, Boolean)] the name, the return type and whether it is a class method
    sig { returns([String, T.nilable(String), T::Boolean]) }
    attr_reader :to_a

    # The declaration of a call of RBI::Scope#create_method.
    # @param name [String]
    # @param options [Hash{Symbol => Object}] the keyword arguments of the call
    # @return [RbiRecorder::Declaration]
    sig { params(name: String, options: T::Hash[Symbol, Object]).returns(Declaration) }
    def self.from(name, options)
      return_type = options[:return_type]
      new(name, (return_type if return_type.is_a?(String)), options.fetch(:class_method, false).equal?(true))
    end

    # @param name [String]
    # @param return_type [String, nil]
    # @param class_method [Boolean]
    sig { params(name: String, return_type: T.nilable(String), class_method: T::Boolean).void }
    def initialize(name, return_type, class_method)
      @to_a = T.let([name, return_type, class_method], [String, T.nilable(String), T::Boolean])
    end

    # @return [String, nil] the method name if it is an instance method
    sig { returns(T.nilable(String)) }
    def instance_method_name
      name, _, class_method = to_a
      name unless class_method
    end

    # @return [String, nil] the method name if it is a class method
    sig { returns(T.nilable(String)) }
    def class_method_name
      name, _, class_method = to_a
      name if class_method
    end
  end

  sig { void }
  def initialize
    @declarations = T.let([], T::Array[Declaration])
  end

  # Mirrors RBI::Tree#create_path: yields the scope for +constant+.
  # @param _constant [Class]
  # @yieldparam scope [RbiRecorder]
  # @return [void]
  sig { params(_constant: T::Module[T.anything], block: T.proc.params(scope: RbiRecorder).void).void }
  def create_path(_constant, &block)
    yield(self)
  end

  # Mirrors RBI::Scope#create_method.
  # @param name [String]
  # @param options [Hash{Symbol => Object}] +return_type:+, +class_method:+ and the other keyword arguments
  # @return [void]
  sig { params(name: String, options: Object).void }
  def create_method(name, **options)
    @declarations << Declaration.from(name, options)
  end

  # The declarations as +[name, return type, class method?]+ triples.
  # @return [Array<Array(String, String, Boolean)>]
  sig { returns(T::Array[[String, T.nilable(String), T::Boolean]]) }
  def triples
    @declarations.map(&:to_a)
  end

  # The names of all declared instance methods.
  # @return [Array<String>]
  sig { returns(T::Array[String]) }
  def instance_method_names
    @declarations.filter_map(&:instance_method_name)
  end

  # The names of all declared class methods.
  # @return [Array<String>]
  sig { returns(T::Array[String]) }
  def class_method_names
    @declarations.filter_map(&:class_method_name)
  end
end
