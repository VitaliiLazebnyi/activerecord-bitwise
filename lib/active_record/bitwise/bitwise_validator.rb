# typed: strict
# frozen_string_literal: true

require 'active_model'
require 'active_record/bitwise/definitions'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

# Custom validator supporting validates :attribute, bitwise: true.
# Works with any ActiveModel-compliant record whose class exposes
# +bitwise_definitions+ (plain ActiveModel classes without definitions are
# silently skipped instead of crashing). Supports the standard :message option.
class BitwiseValidator < ActiveModel::EachValidator
  extend T::Sig

  # Maximum number of invalid values reflected back into the error message.
  MAX_REPORTED_VALUES = 3
  public_constant :MAX_REPORTED_VALUES

  # Maximum length of a single reflected invalid value before truncation.
  MAX_REPORTED_LENGTH = 64
  public_constant :MAX_REPORTED_LENGTH

  # A reflected value, cut to {MAX_REPORTED_LENGTH} characters (marked with an ellipsis when cut).
  # @param value [Object] The invalid value.
  # @return [String]
  sig { params(value: Object).returns(String) }
  def self.reflect(value)
    text = value.to_s
    text.length > MAX_REPORTED_LENGTH ? "#{text[0, MAX_REPORTED_LENGTH]}…" : text
  end

  # Validates that every element of +value+ is present in the column's mapping.
  # @param record [ActiveModel::Validations] Any ActiveModel/ActiveRecord object.
  # @param attribute [Symbol, String] The attribute under validation.
  # @param value [Object, nil] The assigned value.
  # @return [void]
  sig do
    override.params(
      record: T.all(ActiveModel::Validations, Object), attribute: ActiveRecord::Bitwise::Types::Name,
      value: T.nilable(Object)
    ).void
  end
  def validate_each(record, attribute, value)
    invalid = invalid_values(record.class, attribute, value)
    record.errors.add(attribute, options[:message] || default_message(invalid)) unless invalid.empty?
  end

  private

  # The elements of +value+ that are not flags of the attribute.
  # @param klass [Class] The record's class.
  # @param attribute [Symbol, String] The attribute under validation.
  # @param value [Object, nil] The assigned value (nil holds no flags).
  # @return [Array<Object>] None when the class declares no such bitwise column.
  sig do
    params(klass: T::Class[T.anything], attribute: ActiveRecord::Bitwise::Types::Name, value: T.nilable(Object))
      .returns(T::Array[Object])
  end
  def invalid_values(klass, attribute, value)
    mapping = ActiveRecord::Bitwise::Definitions.mapping(klass, attribute)
    return [] unless mapping

    names = mapping.keys.map(&:to_s)
    Array(value).reject { |item| (item in nil | '') || names.include?(item.to_s) }
  end

  # Builds the default error message, truncating both the number of reflected
  # values and their individual lengths to avoid log-injection/amplification.
  # @param invalid_values [Array<Object>] The invalid values.
  # @return [String]
  sig { params(invalid_values: T::Array[Object]).returns(String) }
  def default_message(invalid_values)
    shown = invalid_values.first(MAX_REPORTED_VALUES).map { |value| self.class.reflect(value) }
    hidden = invalid_values.size - MAX_REPORTED_VALUES
    "contains invalid values: #{shown.join(', ')}#{" (and #{hidden} more)" if hidden.positive?}"
  end
end
