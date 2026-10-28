# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/atomic_update'
require 'active_record/bitwise/declaration'
require 'active_record/bitwise/flag'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/redefinition'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Defines the instance and class methods generated for a declared column: the getter, the per-flag
      # `flag?`, `flag=` and `flag!`, and the atomic `add_*!` / `remove_*!` methods.
      #
      # The generated methods run with the record as +self+, which Sorbet cannot see (it types +self+ in a
      # +define_method+ block as this module), so they only forward, by name, to the private type-checked
      # helpers of {InstanceMethods}, where the behavior lives.
      module GeneratedMethods
        extend T::Sig
        extend T::Helpers

        requires_ancestor { T.class_of(ActiveRecord::Base) }

        # The private record method behind the column getter ({InstanceMethods::RawCache}).
        READ = :_bitwise_read
        # The private record methods behind `flag?`, `flag=` and `flag!` ({InstanceMethods::FlagAccess}).
        FLAG_QUERY = :_bitwise_flag_enabled?
        FLAG_ASSIGN = :_bitwise_flag_assign
        FLAG_SAVE = :_bitwise_flag_save
        # The private record method behind the instance-level atomic methods ({InstanceMethods::AtomicOperations}).
        ATOMIC_UPDATE = :_bitwise_atomic_update!
        private_constant :READ, :FLAG_QUERY, :FLAG_ASSIGN, :FLAG_SAVE, :ATOMIC_UPDATE

        private

        # Removes the instance method +name+ when this class itself defines it (a column declared again), so
        # that defining it anew replaces it without Ruby's "method redefined" warning ({Redefinition.release}
        # does the same for class methods; Sorbet does not type +self+ here as a Module that could be passed
        # to it).
        # @param name [String, Symbol] The method name.
        # @return [String, Symbol] +name+.
        sig { params(name: T.any(String, Symbol)).returns(T.any(String, Symbol)) }
        def _bitwise_release(name)
          remove_method(name) if method_defined?(name, false)
          name
        end

        # Defines the column getter that stamps returned arrays with the raw bitmask.
        # @param declaration [ActiveRecord::Bitwise::Declaration]
        # @return [void]
        sig { params(declaration: Declaration).void }
        def _bitwise_define_getter(declaration)
          column = declaration.column
          define_method(_bitwise_release(declaration.column_name)) { __send__(READ, column, super()) }
        end

        # Defines the per-flag `flag?`, `flag=`, and `flag!` methods.
        # @param declaration [ActiveRecord::Bitwise::Declaration]
        # @return [void]
        sig { params(declaration: Declaration).void }
        def _bitwise_define_flag_methods(declaration)
          declaration.flags.each { |name, flag| _bitwise_define_flag(name, flag) }
        end

        # Defines the three methods of one flag.
        # @param name [String] The generated name (prefix, flag and suffix).
        # @param flag [ActiveRecord::Bitwise::Flag] The flag.
        # @return [void]
        sig { params(name: String, flag: Flag).void }
        def _bitwise_define_flag(name, flag)
          define_method(_bitwise_release("#{name}?")) { __send__(FLAG_QUERY, flag) }
          _bitwise_define_flag_writers(name, flag)
        end

        # Defines the `flag=` and `flag!` methods of one flag.
        # @param name [String] The generated name (prefix, flag and suffix).
        # @param flag [ActiveRecord::Bitwise::Flag] The flag.
        # @return [void]
        sig { params(name: String, flag: Flag).void }
        def _bitwise_define_flag_writers(name, flag)
          define_method(_bitwise_release("#{name}=")) { |value| __send__(FLAG_ASSIGN, flag, value) }
          define_method(_bitwise_release("#{name}!")) { __send__(FLAG_SAVE, flag) }
        end

        # Defines the class-level and instance-level atomic add/remove methods.
        # @param declaration [ActiveRecord::Bitwise::Declaration]
        # @return [void]
        sig { params(declaration: Declaration).void }
        def _bitwise_define_atomic_methods(declaration)
          %i[add remove].each do |operation|
            _bitwise_define_class_atomic(operation, declaration.layout)
            _bitwise_define_instance_atomic(operation, declaration.column_name)
          end
        end

        # Defines `add_<column>!` / `remove_<column>!` on the model class, and the private class method that
        # takes the flags as an Array (the instance-level atomic methods use it).
        # @param operation [Symbol] Either :add or :remove.
        # @param layout [ActiveRecord::Bitwise::Layout] The flags of the column.
        # @return [void]
        sig { params(operation: Symbol, layout: Layout).void }
        def _bitwise_define_class_atomic(operation, layout)
          column_name = layout.column_name
          update = :"_bitwise_#{operation}_#{column_name}"
          _bitwise_define_class_update(update, AtomicUpdate.new(operation, layout))
          _bitwise_define_class_atomic_api("#{operation}_#{column_name}!", update)
        end

        # Defines the private class method that updates the given records in one statement.
        # @param name [Symbol] The method to define.
        # @param atomic [ActiveRecord::Bitwise::AtomicUpdate] What to update.
        # @return [void]
        sig { params(name: Symbol, atomic: AtomicUpdate).void }
        def _bitwise_define_class_update(name, atomic)
          Redefinition.release(singleton_class, name)
          define_singleton_method(name) do |values, records|
            plan = atomic.plan(values, records)
            plan && where(id: plan.ids).update_all(plan.assignment(connection))
          end
          private_class_method(name)
        end

        # Defines the public class-level atomic method that forwards to the private one.
        # @param name [String] The public method.
        # @param update [Symbol] The private class method that takes the flags as an Array.
        # @return [void]
        sig { params(name: String, update: Symbol).void }
        def _bitwise_define_class_atomic_api(name, update)
          Redefinition.release(singleton_class, name)
          define_singleton_method(name) { |*values, records:| __send__(update, values, records) }
        end

        # Defines the instance-level atomic methods: `add_<singular>!` and its alias `add_<column>!` (when the
        # column name is already singular, or uncountable, the alias is the method itself, which is harmless).
        # @param operation [Symbol] Either :add or :remove.
        # @param column_name [Symbol, String] The database column name.
        # @return [void]
        sig { params(operation: Symbol, column_name: Types::Name).void }
        def _bitwise_define_instance_atomic(operation, column_name)
          implementation = :"#{operation}_#{column_name.to_s.singularize}!"
          _bitwise_define_atomic_implementation(implementation, operation, column_name.to_sym)
          _bitwise_define_atomic_alias(:"#{operation}_#{column_name}!", implementation)
        end

        # Defines the instance-level atomic method +name+.
        # @param name [Symbol] The method to define.
        # @param operation [Symbol] Either :add or :remove.
        # @param column [Symbol] The database column name.
        # @return [void]
        sig { params(name: Symbol, operation: Symbol, column: Symbol).void }
        def _bitwise_define_atomic_implementation(name, operation, column)
          # No release needed: the method is always aliased (see below), and Ruby does not warn when an
          # aliased method is redefined.
          define_method(name) { |*values| __send__(ATOMIC_UPDATE, column, operation, values) }
        end

        # Defines +name+ as an alias of +implementation+ (Ruby does not warn when an alias replaces a method).
        # @param name [Symbol] The method to define.
        # @param implementation [Symbol] The method it aliases.
        # @return [void]
        sig { params(name: Symbol, implementation: Symbol).void }
        def _bitwise_define_atomic_alias(name, implementation)
          alias_method(name, implementation)
        end
      end
    end
  end
end
