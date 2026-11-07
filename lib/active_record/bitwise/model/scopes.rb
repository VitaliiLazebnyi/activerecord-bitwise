# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/declaration'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/redefinition'
require 'active_record/bitwise/scope_query'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Defines the four query scopes of a column. Column references are table-qualified so the
      # scopes remain unambiguous under joins.
      module Scopes
        extend T::Sig
        extend T::Helpers

        requires_ancestor { T.class_of(ActiveRecord::Base) }

        # The scopes of a column: name prefix and the {ScopeQuery} method that builds the `where` arguments.
        SCOPES = T.let({ with_: :with, with_any_: :with_any, with_exact_: :with_exact, without_: :without }.freeze,
                       T::Hash[Symbol, Symbol])
        private_constant :SCOPES

        private

        # Defines the four query scopes.
        # @param declaration [ActiveRecord::Bitwise::Declaration]
        # @return [void]
        sig { params(declaration: Declaration).void }
        def _bitwise_define_scopes(declaration)
          layout = declaration.layout
          SCOPES.each { |prefix, query| _bitwise_scope("#{prefix}#{layout.column_name}", layout, query) }
        end

        # Defines one scope. The body runs on the relation that the scope is called on, so the table and
        # connection are those of the relation's model.
        # @param name [String] The scope name.
        # @param layout [ActiveRecord::Bitwise::Layout] The flags of the column.
        # @param query [Symbol] The {ScopeQuery} method that builds the `where` arguments.
        # @return [void]
        sig { params(name: String, layout: Layout, query: Symbol).void }
        def _bitwise_scope(name, layout, query)
          Redefinition.release(singleton_class, name)
          # A scope body that returns nil leaves the relation unfiltered (ActiveRecord falls back to `all`).
          scope(name, lambda do |*values|
            clause = ScopeQuery.new(layout, values).public_send(query)
            where(clause.arguments(connection, table_name)) if clause
          end)
        end
      end
    end
  end
end
