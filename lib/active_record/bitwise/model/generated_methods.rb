# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/atomic_update'
require 'active_record/bitwise/declaration'
require 'active_record/bitwise/flag'
require 'active_record/bitwise/layout'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module Model
      # Defines the instance and class methods generated for a declared column: the getter, the per-flag
      # `flag?`, `flag=` and `flag!`, and the atomic `add_*!` / `remove_*!` methods.
      #
      # The generated methods run with the record as +self+, which Sorbet cannot see, so they only forward
      # (by name) to the type-checked helpers of {InstanceMethods}, where the behavior lives.
      module GeneratedMethods
        extend T::Sig
        extend T::Helpers

        requires_ancestor { T.class_of(ActiveRecord::Base) }

        private

        # Defines the column getter that stamps returned arrays with the raw bitmask.
        # @param declaration [ActiveRecord::Bitwise::Declaration]
        # @return [void]
        sig { params(declaration: Declaration).void }
        def _bitwise_define_getter(declaration)
          column = declaration.column
          define_method(declaration.column_name) { __send__(:_bitwise_read, column, super()) }
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
          define_method("#{name}?") { __send__(:_bitwise_flag_enabled?, flag) }
          _bitwise_define_flag_writers(name, flag)
        end

        # Defines the `flag=` and `flag!` methods of one flag.
        # @param name [String] The generated name (prefix, flag and suffix).
        # @param flag [ActiveRecord::Bitwise::Flag] The flag.
        # @return [void]
        sig { params(name: String, flag: Flag).void }
        def _bitwise_define_flag_writers(name, flag)
          define_method("#{name}=") { |value| __send__(:_bitwise_flag_assign, flag, value) }
          define_method("#{name}!") { __send__(:_bitwise_flag_save, flag) }
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
          define_singleton_method(name) do |values, records|
            plan = atomic.plan(values, records)
            plan && where(id: plan.ids).update_all(plan.assignment(connection))
          end
          singleton_class.__send__(:private, name)
        end

        # Defines the public class-level atomic method that forwards to the private one.
        # @param name [String] The public method.
        # @param update [Symbol] The private class method that takes the flags as an Array.
        # @return [void]
        sig { params(name: String, update: Symbol).void }
        def _bitwise_define_class_atomic_api(name, update)
          define_singleton_method(name) { |*values, records:| __send__(update, values, records) }
        end

        # Defines the instance-level atomic methods. When the column name is already singular
        # (or uncountable), only one method is defined — defining an alias with the
        # same name would overwrite the implementation and recurse infinitely.
        # @param operation [Symbol] Either :add or :remove.
        # @param column_name [Symbol, String] The database column name.
        # @return [void]
        sig { params(operation: Symbol, column_name: Types::Name).void }
        def _bitwise_define_instance_atomic(operation, column_name)
          implementation = "#{operation}_#{column_name.to_s.singularize}!"
          column = column_name.to_sym
          define_method(implementation) { |*values| __send__(:_bitwise_atomic_update!, column, operation, values) }
          _bitwise_define_atomic_alias("#{operation}_#{column_name}!", implementation)
        end

        # Defines +name+ as an alias of +implementation+, unless that is the same name.
        # @param name [String] The method to define.
        # @param implementation [String] The method it forwards to.
        # @return [void]
        sig { params(name: String, implementation: String).void }
        def _bitwise_define_atomic_alias(name, implementation)
          define_method(name) { |*values| method(implementation).call(*values) } unless name == implementation
        end
      end
    end
  end
end
