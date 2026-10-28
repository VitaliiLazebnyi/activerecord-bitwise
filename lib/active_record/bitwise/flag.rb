# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # One flag of one column, as seen by the generated `flag?`, `flag=` and `flag!` methods of a record.
    class Flag
      extend T::Sig

      # A record that carries flags: a model instance with the flag access methods.
      Holder = T.type_alias { InstanceMethods::FlagAccess }
      public_constant :Holder

      # The database column name.
      # @return [Symbol, String]
      sig { returns(Types::Name) }
      attr_reader :column_name

      # The flag name.
      # @return [Symbol]
      sig { returns(Symbol) }
      attr_reader :key

      # @param column_name [Symbol, String] The database column name.
      # @param key [Symbol] The flag name.
      sig { params(column_name: Types::Name, key: Symbol).void }
      def initialize(column_name, key)
        @column_name = column_name
        @key = key
      end

      # The name of the setter of the column.
      # @return [String]
      sig { returns(String) }
      def writer
        "#{column_name}="
      end

      # Sets the flag on +record+ through the setter of its column.
      # @param record [InstanceMethods::FlagAccess] A model record.
      # @return [void]
      sig { params(record: Holder).void }
      def set(record)
        record._bitwise_flags_write(writer, added_to(record._bitwise_flags(column_name)))
      end

      # Clears the flag on +record+ through the setter of its column.
      # @param record [InstanceMethods::FlagAccess] A model record.
      # @return [void]
      sig { params(record: Holder).void }
      def clear(record)
        record._bitwise_flags_write(writer, removed_from(record._bitwise_flags(column_name)))
      end

      # Whether the flag is set on +record+.
      # @param record [InstanceMethods::FlagAccess] A model record.
      # @return [Boolean]
      sig { params(record: Holder).returns(T::Boolean) }
      def set?(record)
        in?(record._bitwise_flags(column_name))
      end

      # Whether the flag is among +flags+.
      # @param flags [Array<Object>] The flags of a record.
      # @return [Boolean]
      sig { params(flags: T::Array[Object]).returns(T::Boolean) }
      def in?(flags)
        flags.include?(key)
      end

      # A copy of +flags+ that includes the flag.
      # @param flags [Array<Object>] The flags of a record.
      # @return [Array<Object>]
      sig { params(flags: T::Array[Object]).returns(T::Array[Object]) }
      def added_to(flags)
        copy = flags.dup
        copy << key unless in?(copy)
        copy
      end

      # A copy of +flags+ without the flag.
      # @param flags [Array<Object>] The flags of a record.
      # @return [Array<Object>]
      sig { params(flags: T::Array[Object]).returns(T::Array[Object]) }
      def removed_from(flags)
        copy = flags.dup
        copy.delete(key)
        copy
      end
    end
  end
end
