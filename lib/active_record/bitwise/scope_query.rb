# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # One call of a generated scope. Each method returns the {Clause} to pass to `where`, or nil when the
    # scope selects every record.
    #
    # @note `with_` and `with_any_` silently drop unrecognized values, matching nothing (+1=0+) only if ALL
    #   values are invalid. `with_exact_` matches nothing if ANY value is invalid (strict validation).
    #   `without_` drops unrecognized values and selects every record if none are valid.
    class ScopeQuery
      extend T::Sig

      # A `where` condition on a column: SQL that refers to the column through a placeholder, and its
      # bound values.
      class Clause
        extend T::Sig

        # What stands for the qualified, quoted column reference in the SQL.
        COLUMN = '{column}'
        public_constant :COLUMN

        # @param sql [String] The SQL, with {COLUMN} where the column is referenced.
        # @param binds [Array<Object>] The values bound to its placeholders.
        # @param column_name [Symbol, String] The database column name.
        sig { params(sql: String, binds: T::Array[Object], column_name: Types::Name).void }
        def initialize(sql, binds, column_name)
          @sql = sql
          @binds = binds
          @column_name = column_name
        end

        # The arguments for `where`. The column is qualified with the table, which keeps the scopes
        # unambiguous under joins.
        # @param adapter [ActiveRecord::ConnectionAdapters::AbstractAdapter] The database connection.
        # @param table_name [String] The table of the model.
        # @return [Array<Object>]
        sig { params(adapter: ActiveRecord::ConnectionAdapters::AbstractAdapter, table_name: String).returns(T::Array[Object]) }
        def arguments(adapter, table_name)
          column = "#{adapter.quote_table_name(table_name)}.#{adapter.quote_column_name(@column_name)}"
          [@sql.gsub(COLUMN) { column }, *@binds]
        end
      end

      # The scope arguments without nil and empty strings.
      # @param values [Array<Object>] The scope arguments.
      # @return [Array<Object>]
      sig { params(values: T::Array[Object]).returns(T::Array[Object]) }
      def self.clean(values)
        list = values.flatten
        list.reject! { |value| value in nil | '' }
        list
      end

      # @param layout [ActiveRecord::Bitwise::Layout] The flags of the column.
      # @param values [Array<Object>] The scope arguments.
      sig { params(layout: Layout, values: T::Array[Object]).void }
      def initialize(layout, values)
        @layout = layout
        @values = values
        @cleaned = T.let(self.class.clean(values), T::Array[Object])
      end

      # Records that have all of the flags (or none, for 0).
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause, nil]
      sig { returns(T.nilable(Clause)) }
      def with
        return if @values.empty?
        return no_flags if @cleaned.empty? || @cleaned.include?(0) || @cleaned.include?('0')

        matching("#{Clause::COLUMN} & ? = ?", 2)
      end

      # Records that have at least one of the flags.
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause, nil]
      sig { returns(T.nilable(Clause)) }
      def with_any
        return if @cleaned.empty?

        matching("#{Clause::COLUMN} & ? > 0", 1)
      end

      # Records that have exactly the flags (and none else).
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause]
      sig { returns(Clause) }
      def with_exact
        return no_flags if @cleaned.empty?
        return none unless @cleaned.all? { |value| @layout.mapped?(value) }

        clause("#{Clause::COLUMN} = ?", [@layout.mask(@cleaned)])
      end

      # Records that have none of the flags.
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause, nil]
      sig { returns(T.nilable(Clause)) }
      def without
        mask = @layout.mask(@cleaned)
        return if mask.zero?

        clause("COALESCE(#{Clause::COLUMN}, 0) & ? = 0", [mask])
      end

      private

      # A condition on the column.
      # @param sql [String] The SQL, with {Clause::COLUMN} where the column is referenced.
      # @param binds [Array<Object>] The values bound to its placeholders.
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause]
      sig { params(sql: String, binds: T::Array[Object]).returns(Clause) }
      def clause(sql, binds = [])
        Clause.new(sql, binds, @layout.column_name)
      end

      # The condition that matches nothing.
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause]
      sig { returns(Clause) }
      def none
        clause('1=0')
      end

      # The condition for "no flags": the column is 0, or NULL (which reads as no flags).
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause]
      sig { returns(Clause) }
      def no_flags
        clause("(#{Clause::COLUMN} = 0 OR #{Clause::COLUMN} IS NULL)")
      end

      # The condition built from the mask of the recognized flags, or nothing matches when there are none.
      # @param sql [String] The SQL, with one placeholder per copy of the mask.
      # @param copies [Integer] How often the mask is bound.
      # @return [ActiveRecord::Bitwise::ScopeQuery::Clause]
      sig { params(sql: String, copies: Integer).returns(Clause) }
      def matching(sql, copies)
        mask = @layout.mask(@cleaned)
        mask.zero? ? none : clause(sql, [mask] * copies)
      end
    end
  end
end
