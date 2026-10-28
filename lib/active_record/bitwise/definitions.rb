# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Questions about the bitwise definitions a class may or may not have (a class has them once it extends
    # {Model}).
    module Definitions
      extend T::Sig

      # Whether +klass+ declares bitwise columns (it publicly responds to +bitwise_definitions+).
      # @param klass [Module] A class or module. (Declared +T.untyped+: the check is duck-typed, any class
      #   with a public +bitwise_definitions+ qualifies, which no static type can express.)
      # @return [Boolean]
      sig { params(klass: T.untyped).returns(T::Boolean) }
      def self.bitwise?(klass)
        klass.respond_to?(:bitwise_definitions)
      end

      # The flag mapping of a bitwise column.
      # @param klass [Class] A class, which may or may not declare bitwise columns. (Declared +T.untyped+ for
      #   the same reason as in {bitwise?}.)
      # @param attribute [Symbol, String] The column.
      # @return [Hash{Symbol => Integer}, nil] Nil when +klass+ declares no such bitwise column.
      sig { params(klass: T.untyped, attribute: Types::Name).returns(T.nilable(Types::Positions)) }
      def self.mapping(klass, attribute)
        return unless bitwise?(klass)

        klass.bitwise_definitions[attribute.to_sym]&.fetch(:mapping)
      end
    end
  end
end
