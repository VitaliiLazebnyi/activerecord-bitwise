# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Generators of the methods defined for each bitwise column.
      module Definers
        # Defines the four query scopes. Column references are table-qualified so the
        # scopes remain unambiguous under joins.
        # @note `with_` and `with_any_` silently drop unrecognized values, returning
        #   `where('1=0')` (empty) only if ALL values are invalid. `with_exact_` returns
        #   `where('1=0')` if ANY value is invalid (strict validation). `without_` drops
        #   unrecognized values and returns `all` if none are valid.
        class Scopes
          extend T::Sig

          # Scope name prefix and the query method implementing it.
          SCOPES = T.let([%w[with_ with_all], %w[with_any_ with_any], %w[with_exact_ with_exact],
                          %w[without_ without]].freeze, T::Array[[String, String]])
          private_constant :SCOPES

          # Defines `with_`, `with_any_`, `with_exact_` and `without_` scopes on +model+.
          # @param model [T.untyped] The model class being configured.
          # @param column_name [T.any(Symbol, String)]
          # @param mapping [T::Hash[Symbol, Integer]]
          # @return [void]
          sig { params(model: T.untyped, column_name: Types::Name, mapping: Types::Positions).void }
          def self.define(model, column_name, mapping)
            builder = new(column_name, mapping)
            SCOPES.each { |prefix, query| define_scope(model, builder, "#{prefix}#{column_name}", query) }
          end

          # @param column_name [T.any(Symbol, String)]
          # @param mapping [T::Hash[Symbol, Integer]]
          sig { params(column_name: Types::Name, mapping: Types::Positions).void }
          def initialize(column_name, mapping)
            @column_name = column_name
            @mapping = mapping
            @mapping_strings = T.let(mapping.keys.map(&:to_s), T::Array[String])
          end

          # Records containing ALL of +values+ (`0`/`'0'`/empty means "no flags set").
          # @param relation [T.untyped]
          # @param values [T::Array[T.untyped]]
          # @return [T.untyped]
          sig { params(relation: T.untyped, values: T::Array[T.untyped]).returns(T.untyped) }
          def with_all(relation, values)
            return relation.all if values.empty?

            cleaned = clean(values)
            return relation.where("#{qualified(relation)} = 0") if cleaned.empty? || zero?(cleaned)

            mask = mask_of_valid(cleaned)
            mask ? relation.where("#{qualified(relation)} & ? = ?", mask, mask) : relation.where('1=0')
          end

          # Records containing ANY of +values+.
          # @param relation [T.untyped]
          # @param values [T::Array[T.untyped]]
          # @return [T.untyped]
          sig { params(relation: T.untyped, values: T::Array[T.untyped]).returns(T.untyped) }
          def with_any(relation, values)
            cleaned = clean(values)
            return relation.all if cleaned.empty?

            mask = mask_of_valid(cleaned)
            mask ? relation.where("#{qualified(relation)} & ? > 0", mask) : relation.where('1=0')
          end

          # Records whose flags are exactly +values+ (any unknown value matches nothing).
          # @param relation [T.untyped]
          # @param values [T::Array[T.untyped]]
          # @return [T.untyped]
          sig { params(relation: T.untyped, values: T::Array[T.untyped]).returns(T.untyped) }
          def with_exact(relation, values)
            cleaned = clean(values)
            return relation.where("#{qualified(relation)} = 0") if cleaned.empty?
            return relation.where('1=0') if valid(cleaned).size < cleaned.size

            relation.where("#{qualified(relation)} = ?", mask_of(valid(cleaned)))
          end

          # Records containing NONE of +values+ (unknown values are ignored).
          # @param relation [T.untyped]
          # @param values [T::Array[T.untyped]]
          # @return [T.untyped]
          sig { params(relation: T.untyped, values: T::Array[T.untyped]).returns(T.untyped) }
          def without(relation, values)
            flags = valid(clean(values))
            return relation.all if flags.empty?

            relation.where("#{qualified(relation)} & ? = 0", mask_of(flags))
          end

          # Defines one scope delegating to a query method of +builder+.
          # @param model [T.untyped]
          # @param builder [Scopes]
          # @param name [String] The scope name.
          # @param query [String] The query method of +builder+.
          # @return [void]
          sig { params(model: T.untyped, builder: Scopes, name: String, query: String).void }
          def self.define_scope(model, builder, name, query)
            model.scope(name, ->(*values) { builder.public_send(query, self, values) })
          end
          private_class_method :define_scope

          private

          # Drops nil and empty-string values.
          # @param values [T::Array[T.untyped]]
          # @return [T::Array[T.untyped]]
          sig { params(values: T::Array[T.untyped]).returns(T::Array[T.untyped]) }
          def clean(values)
            flat = values.flatten
            flat.reject! { |value| value.nil? || value == '' }
            flat
          end

          # Whether the (cleaned) values ask for the empty flag set.
          # @param cleaned [T::Array[T.untyped]]
          # @return [Boolean]
          sig { params(cleaned: T::Array[T.untyped]).returns(T::Boolean) }
          def zero?(cleaned)
            cleaned.include?(0) || cleaned.include?('0')
          end

          # Mapped flags among +cleaned+ (names compared as strings: no Symbol conversion of input).
          # @param cleaned [T::Array[T.untyped]]
          # @return [T::Array[Symbol]]
          sig { params(cleaned: T::Array[T.untyped]).returns(T::Array[Symbol]) }
          def valid(cleaned)
            cleaned.filter_map { |value| value.to_s.to_sym if @mapping_strings.include?(value.to_s) }
          end

          # The union of the bits of +flags+.
          # @param flags [T::Array[Symbol]]
          # @return [Integer]
          sig { params(flags: T::Array[Symbol]).returns(Integer) }
          def mask_of(flags)
            flags.reduce(0) { |acc, elem| acc | (1 << T.must(@mapping[elem])) }
          end

          # The mask of the mapped flags among +cleaned+.
          # @param cleaned [T::Array[T.untyped]]
          # @return [T.nilable(Integer)] Nil when none of the values is a mapped flag.
          sig { params(cleaned: T::Array[T.untyped]).returns(T.nilable(Integer)) }
          def mask_of_valid(cleaned)
            flags = valid(cleaned)
            mask_of(flags) unless flags.empty?
          end

          # The table-qualified, quoted column reference.
          # @param relation [T.untyped]
          # @return [String]
          sig { params(relation: T.untyped).returns(String) }
          def qualified(relation)
            connection = relation.connection
            "#{connection.quote_table_name(relation.table_name)}.#{connection.quote_column_name(@column_name)}"
          end
        end
      end
    end
  end
end
