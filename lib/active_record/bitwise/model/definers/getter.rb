# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/raw_mask'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Generators of the methods defined for each bitwise column.
      module Definers
        # Defines the column getter, which stamps returned arrays with the raw bitmask.
        module Getter
          extend T::Sig

          # Defines the column getter on +model+.
          # @param model [T.untyped] The model class being configured.
          # @param column_name [T.any(Symbol, String)]
          # @return [void]
          sig { params(model: T.untyped, column_name: Types::Name).void }
          def self.define(model, column_name)
            column = column_name.to_sym
            model.define_method(column_name) do
              record = T.unsafe(self)
              raw = record._bitwise_hydrate_raw_cache(column)
              Getter.stamped(record.class.attribute_types.fetch(column_name.to_s), super(), raw)
            end
          end

          # Returns +value+ as a frozen array carrying +raw+, unless it already is one.
          # NULL values read as the empty array.
          # @param type [ActiveRecord::Bitwise::Type]
          # @param value [T.untyped] The attribute value.
          # @param raw [Integer] The cached raw bitmask.
          # @return [T.untyped]
          sig { params(type: T.untyped, value: T.untyped, raw: Integer).returns(T.untyped) }
          def self.stamped(type, value, raw)
            value = type.deserialize(nil) if value.nil?
            return value unless value.is_a?(Array) && (!value.frozen? || !RawMask.stamped?(value))

            RawMask.stamp(value.dup, raw).freeze
          end
        end
      end
    end
  end
end
