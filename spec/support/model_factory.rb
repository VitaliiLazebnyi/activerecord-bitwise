# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Builds throwaway ActiveRecord models so that no example mutates a class that
# another example uses.
module ModelFactory
  extend T::Sig

  module_function

  # Creates an anonymous model class that reports +name+ as its class name.
  # @param table [String] the table backing the model
  # @param name [String] the name the class reports (ActiveModel requires one)
  # @param parent [Class] the superclass
  # @yield the block is evaluated in the new class, typically calling +bitwise+
  # @return [Class] the new model class
  sig do
    params(
      table: String,
      name: String,
      parent: T.class_of(ActiveRecord::Base),
      definition: T.nilable(
        T.proc.bind(T.class_of(ActiveRecord::Base)).params(model: T.class_of(ActiveRecord::Base)).void
      )
    ).returns(T.class_of(ActiveRecord::Base))
  end
  def build_model(table = 'users', name: 'TestModel', parent: ActiveRecord::Base, &definition)
    model = anonymous_model(parent, table, name)
    model.class_eval(&definition) if definition
    model
  end

  # A new subclass of +parent+ backed by +table+ that reports +name+ as its class name.
  # @param parent [Class] the superclass
  # @param table [String] the table backing the model
  # @param name [String] the name the class reports
  # @return [Class]
  sig do
    params(parent: T.class_of(ActiveRecord::Base), table: String, name: String).returns(T.class_of(ActiveRecord::Base))
  end
  def anonymous_model(parent, table, name)
    model = Class.new(parent)
    model.table_name = table
    model.define_singleton_method(:name) { name }
    model
  end

  # Builds a plain (non ActiveRecord) ActiveModel class whose +roles+ attribute is
  # validated with the bitwise validator.
  # @return [Class]
  sig { returns(T.class_of(PlainModel)) }
  def build_plain_validated_model
    Class.new(PlainModel)
  end

  # Generates a string that is guaranteed not to exist as a Symbol yet.
  # @return [String]
  sig { returns(String) }
  def unique_unmapped_name
    "unmapped_#{SecureRandom.hex(12)}"
  end

  # Whether a Symbol with the given name exists in the process-wide symbol table.
  # @param name [String]
  # @return [Boolean]
  sig { params(name: String).returns(T::Boolean) }
  def symbol_exists?(name)
    Symbol.all_symbols.any? { |symbol| symbol.name == name }
  end

  # A plain (non ActiveRecord) ActiveModel model whose +roles+ attribute is validated with the bitwise
  # validator. {ModelFactory.build_plain_validated_model} subclasses it, so that no example changes it.
  class PlainModel
    extend T::Sig
    include ActiveModel::Validations

    # The validated value.
    # @return [Object]
    sig { returns(T.anything) }
    attr_reader :roles

    validates(:roles, bitwise: true)

    # The name ActiveModel reports in validation messages.
    # @return [String]
    sig { returns(String) }
    def self.name
      'PlainModel'
    end

    # @param roles [Object] the value to validate
    sig { params(roles: T.anything).void }
    def initialize(roles)
      @roles = roles
    end
  end
end
