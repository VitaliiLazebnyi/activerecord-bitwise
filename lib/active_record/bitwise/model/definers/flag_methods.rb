# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Generators of the methods defined for each bitwise column.
      module Definers
        # Defines the per-flag `flag?`, `flag=`, and `flag!` methods.
        module FlagMethods
          extend T::Sig

          # Defines the three methods of every flag on +model+.
          # @param model [T.untyped] The model class being configured.
          # @param column_name [T.any(Symbol, String)]
          # @param mapping [T::Hash[Symbol, Integer]]
          # @param prefix [String]
          # @param suffix [String]
          # @return [void]
          sig do
            params(model: T.untyped, column_name: Types::Name, mapping: Types::Positions,
                   prefix: String, suffix: String).void
          end
          def self.define(model, column_name, mapping, prefix, suffix)
            mapping.each_key do |key|
              name = "#{prefix}#{key}#{suffix}"
              define_predicate(model, "#{name}?", column_name, key)
              define_setter(model, "#{name}=", column_name, key)
              define_persister(model, "#{name}!", column_name, key)
            end
          end

          # Defines `flag?`.
          # @param model [T.untyped]
          # @param method_name [String]
          # @param column_name [T.any(Symbol, String)]
          # @param key [Symbol]
          # @return [void]
          sig { params(model: T.untyped, method_name: String, column_name: Types::Name, key: Symbol).void }
          def self.define_predicate(model, method_name, column_name, key)
            model.define_method(method_name) { Array(T.unsafe(self).public_send(column_name)).include?(key) }
          end
          private_class_method :define_predicate

          # Defines `flag=`. Uses ActiveModel boolean semantics: "0", "false", "", "off", 0
          # disable the flag (matching Rails checkbox conventions) instead of raw Ruby truthiness.
          # @param model [T.untyped]
          # @param method_name [String]
          # @param column_name [T.any(Symbol, String)]
          # @param key [Symbol]
          # @return [void]
          sig { params(model: T.untyped, method_name: String, column_name: Types::Name, key: Symbol).void }
          def self.define_setter(model, method_name, column_name, key)
            model.define_method(method_name) { |value| T.unsafe(self)._bitwise_assign_flag(column_name, key, value) }
          end
          private_class_method :define_setter

          # Defines `flag!`.
          # @note This is a convenience wrapper that performs a full `save!` cycle
          #   (validations, callbacks, dirty tracking). It is NOT an atomic SQL operation.
          #   If a validation on another attribute fails, this will raise
          #   `ActiveRecord::RecordInvalid`. For truly atomic operations, use the
          #   instance-level `add_<singular>!` method instead.
          # @param model [T.untyped]
          # @param method_name [String]
          # @param column_name [T.any(Symbol, String)]
          # @param key [Symbol]
          # @return [void]
          sig { params(model: T.untyped, method_name: String, column_name: Types::Name, key: Symbol).void }
          def self.define_persister(model, method_name, column_name, key)
            model.define_method(method_name) do
              record = T.unsafe(self)
              record._bitwise_assign_flag(column_name, key, true)
              record.save!
            end
          end
          private_class_method :define_persister
        end
      end
    end
  end
end
