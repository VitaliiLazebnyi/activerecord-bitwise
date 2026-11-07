# typed: false
# frozen_string_literal: true

# Builds throwaway ActiveRecord models so that no example mutates a class that
# another example uses.
module ModelFactory
  # Creates an anonymous model class that reports +name+ as its class name.
  # @param table [String] the table backing the model
  # @param name [String] the name the class reports (ActiveModel requires one)
  # @param parent [Class] the superclass
  # @yield the block is evaluated in the new class, typically calling +bitwise+
  # @return [Class] the new model class
  def build_model(table = 'users', name: 'TestModel', parent: ActiveRecord::Base, &definition)
    model = Class.new(parent)
    model.table_name = table
    model.define_singleton_method(:name) { name }
    model.class_eval(&definition) if definition
    model
  end

  # Builds a plain (non ActiveRecord) ActiveModel class whose +roles+ attribute is
  # validated with the bitwise validator.
  # @return [Class]
  def build_plain_validated_model
    model = Class.new
    model.include(ActiveModel::Model)
    model.attr_accessor :roles
    model.define_singleton_method(:name) { 'PlainModel' }
    model.validates :roles, bitwise: true
    model
  end

  # Generates a string that is guaranteed not to exist as a Symbol yet.
  # @return [String]
  def unique_unmapped_name
    "unmapped_#{SecureRandom.hex(12)}"
  end

  # Whether a Symbol with the given name exists in the process-wide symbol table.
  # @param name [String]
  # @return [Boolean]
  def symbol_exists?(name)
    Symbol.all_symbols.any? { |symbol| symbol.name == name }
  end
end
