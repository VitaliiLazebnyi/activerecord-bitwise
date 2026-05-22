# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'
require 'active_model'

# Custom validator supporting validates :attribute, bitwise: true
class BitwiseValidator < ActiveModel::EachValidator
  extend T::Sig

  sig { override.params(record: ActiveRecord::Base, attribute: Symbol, value: T.untyped).void }
  def validate_each(record, attribute, value)
    return if value.nil?

    definition = T.unsafe(record.class).bitwise_definitions[attribute.to_sym]
    return unless definition

    mapping = definition[:mapping]
    mapping_strings = mapping.keys.map(&:to_s)
    invalid_values = Kernel.Array(value).reject { |val| val.nil? || val == '' || mapping_strings.include?(val.to_s) }

    return unless invalid_values.any?

    T.unsafe(record).errors.add(attribute, "contains invalid values: #{invalid_values.join(', ')}")
  end
end
