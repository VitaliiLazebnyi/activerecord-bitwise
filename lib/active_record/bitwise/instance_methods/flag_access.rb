# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/flag'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # The behavior behind the generated per-flag methods (`flag?`, `flag=` and `flag!`), which only
      # forward here.
      module FlagAccess
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }
        requires_ancestor { Object }

        # Whether the flag is set.
        # @param flag [ActiveRecord::Bitwise::Flag]
        # @return [Boolean]
        sig { params(flag: Flag).returns(T::Boolean) }
        def _bitwise_flag_enabled?(flag)
          flag.set?(self)
        end

        # Sets or clears the flag. Uses ActiveModel boolean semantics: "0", "false", "", "off", 0 disable the
        # flag (matching Rails checkbox conventions) instead of raw Ruby truthiness.
        # @param flag [ActiveRecord::Bitwise::Flag]
        # @param value [Object, nil] The assigned value.
        # @return [void]
        sig { params(flag: Flag, value: T.nilable(Object)).void }
        def _bitwise_flag_assign(flag, value)
          BOOLEAN_TYPE.cast(value) ? flag.set(self) : flag.clear(self)
        end

        # Sets the flag and saves the record. This is a convenience wrapper that performs a full `save!`
        # cycle (validations, callbacks, dirty tracking). It is NOT an atomic SQL operation. If a validation
        # on another attribute fails, this raises `ActiveRecord::RecordInvalid`. For truly atomic operations,
        # use the instance-level `add_<singular>!` method instead.
        # @param flag [ActiveRecord::Bitwise::Flag]
        # @return [Boolean]
        sig { params(flag: Flag).returns(T::Boolean) }
        def _bitwise_flag_save(flag)
          flag.set(self)
          save!
        end

        # The current flags of a column.
        # @param column_name [Symbol, String]
        # @return [Array<Object>]
        sig { params(column_name: Types::Name).returns(T::Array[Object]) }
        def _bitwise_flags(column_name)
          Array(public_send(column_name))
        end

        # Assigns +flags+ through the column setter.
        # @param writer [String] The name of the setter.
        # @param flags [Array<Object>]
        # @return [void]
        sig { params(writer: String, flags: T::Array[Object]).void }
        def _bitwise_flags_write(writer, flags)
          public_send(writer, flags)
        end
      end
    end
  end
end
