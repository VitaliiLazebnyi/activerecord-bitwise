# typed: false
# frozen_string_literal: true

# Stands in for Tapioca's RBI tree (the external boundary of the Tapioca DSL compiler):
# it plays both the root and the model scope, and records every method the compiler declares.
class RbiRecorder
  # One declared method.
  Declaration = Struct.new(:name, :return_type, :class_method)
  public_constant :Declaration

  # @return [Array<Declaration>] the declared methods, in declaration order
  attr_reader :declarations

  def initialize
    @declarations = []
  end

  # Mirrors RBI::Tree#create_path: yields the scope for +constant+.
  # @param _constant [Class]
  # @yieldparam scope [RbiRecorder]
  # @return [void]
  def create_path(_constant)
    yield self
  end

  # Mirrors RBI::Scope#create_method.
  # @param name [String]
  # @param return_type [String, nil]
  # @param class_method [Boolean]
  # @return [void]
  def create_method(name, return_type: nil, class_method: false, **)
    @declarations << Declaration.new(name, return_type, class_method)
  end

  # The declarations as +[name, return type, class method?]+ triples.
  # @return [Array<Array(String, String, Boolean)>]
  def triples
    @declarations.map { |declaration| [declaration.name, declaration.return_type, declaration.class_method] }
  end

  # The names of all declared instance methods.
  # @return [Array<String>]
  def instance_method_names
    @declarations.filter_map { |declaration| declaration.name unless declaration.class_method }
  end

  # The names of all declared class methods.
  # @return [Array<String>]
  def class_method_names
    @declarations.filter_map { |declaration| declaration.name if declaration.class_method }
  end
end
