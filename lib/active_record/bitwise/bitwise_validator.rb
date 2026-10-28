# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'active_model'

# Custom validator supporting validates :attribute, bitwise: true.
# Works with any ActiveModel-compliant record whose class exposes
# +bitwise_definitions+ (plain ActiveModel classes without definitions are
# silently skipped instead of crashing). Supports the standard :message option.
class BitwiseValidator < ActiveModel::EachValidator
  extend T::Sig

  # Maximum number of invalid values reflected back into the error message.
  MAX_REPORTED_VALUES = 3

  # Maximum length of a single reflected invalid value before truncation.
  MAX_REPORTED_LENGTH = 64

  # Validates that every element of +value+ is present in the column's mapping.
  # @param record [T.untyped] Any ActiveModel/ActiveRecord object.
  # @param attribute [T.untyped] The attribute under validation.
  # @param value [T.untyped] The assigned value.
  # @return [void]
  sig { override.params(record: T.untyped, attribute: T.untyped, value: T.untyped).void }
  def validate_each(record, attribute, value)
    return if value.nil?
    return unless record.class.respond_to?(:bitwise_definitions)

    definition = T.unsafe(record.class).bitwise_definitions[attribute.to_sym]
    return unless definition

    mapping = definition[:mapping]
    mapping_strings = mapping.keys.map(&:to_s)
    invalid_values = Array(value).reject { |val| val.nil? || val == '' || mapping_strings.include?(val.to_s) }

    return unless invalid_values.any?

    T.unsafe(record).errors.add(attribute, T.unsafe(options[:message]) || default_message(invalid_values))
  end

  private

  # Builds the default error message, truncating both the number of reflected
  # values and their individual lengths to avoid log-injection/amplification.
  # @param invalid_values [T::Array[T.untyped]] The invalid values.
  # @return [String]
  sig { params(invalid_values: T::Array[T.untyped]).returns(String) }
  def default_message(invalid_values)
    shown = invalid_values.first(MAX_REPORTED_VALUES).map do |value|
      str = value.to_s
      str.length > MAX_REPORTED_LENGTH ? "#{str[0, MAX_REPORTED_LENGTH]}…" : str
    end
    suffix = invalid_values.size > MAX_REPORTED_VALUES ? " (and #{invalid_values.size - MAX_REPORTED_VALUES} more)" : ''
    "contains invalid values: #{shown.join(', ')}#{suffix}"
  end
end
