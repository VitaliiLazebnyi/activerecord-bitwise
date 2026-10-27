# typed: strict
# frozen_string_literal: true

require 'active_model'
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

  # Validates that every element of +value+ is present in the column's mapping.
  # @param record [T.untyped] Any ActiveModel/ActiveRecord object.
  # @param attribute [T.untyped] The attribute under validation.
  # @param value [T.untyped] The assigned value.
  # @return [void]
  sig { override.params(record: T.untyped, attribute: T.untyped, value: T.untyped).void }
  def validate_each(record, attribute, value)
    return if value.nil?

    invalid = invalid_values(record, attribute, value)
    return if invalid.none?

    T.unsafe(record).errors.add(attribute, T.unsafe(options[:message]) || default_message(invalid))
  end

  private

  # The elements of +value+ that are not part of the attribute's mapping.
  # @param record [T.untyped] Any ActiveModel/ActiveRecord object.
  # @param attribute [T.untyped] The attribute under validation.
  # @param value [T.untyped] The assigned value.
  # @return [T::Array[T.untyped]] Empty when the attribute has no bitwise definition.
  sig { params(record: T.untyped, attribute: T.untyped, value: T.untyped).returns(T::Array[T.untyped]) }
  def invalid_values(record, attribute, value)
    return [] unless record.class.respond_to?(:bitwise_definitions)

    definition = T.unsafe(record.class).bitwise_definitions[attribute.to_sym]
    return [] unless definition

    names = definition[:mapping].keys.map(&:to_s)
    Array(value).reject { |element| element.nil? || element == '' || names.include?(element.to_s) }
  end

  # Builds the default error message, truncating both the number of reflected
  # values and their individual lengths to avoid log-injection/amplification.
  # @param invalid_values [T::Array[T.untyped]] The invalid values.
  # @return [String]
  sig { params(invalid_values: T::Array[T.untyped]).returns(String) }
  def default_message(invalid_values)
    shown = invalid_values.first(MAX_REPORTED_VALUES).map { |value| truncate(value.to_s) }
    hidden = invalid_values.size - MAX_REPORTED_VALUES
    suffix = hidden.positive? ? " (and #{hidden} more)" : ''
    "contains invalid values: #{shown.join(', ')}#{suffix}"
  end

  # Truncates +text+ to {MAX_REPORTED_LENGTH} characters, marking the cut with an ellipsis.
  # @param text [String]
  # @return [String]
  sig { params(text: String).returns(String) }
  def truncate(text)
    text.length > MAX_REPORTED_LENGTH ? "#{text[0, MAX_REPORTED_LENGTH]}…" : text
  end
end
