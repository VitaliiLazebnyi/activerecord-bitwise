# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/types'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # The keyword options of the `bitwise` macro: +default:+, +prefix:+ and +suffix:+. Values of the wrong
    # type are rejected with a TypeError, unknown keywords with an ArgumentError.
    class Options
      extend T::Sig

      # The +prefix:+ / +suffix:+ option: a name, or +true+ for the singular column name.
      Affix = T.type_alias { T.nilable(T.any(Symbol, String, T::Boolean)) }
      public_constant :Affix

      # Any value an option may hold.
      Value = T.type_alias { T.nilable(T.any(Symbol, String, T::Boolean, Types::Flags)) }
      public_constant :Value

      # The option names the macro accepts.
      KEYS = %i[default prefix suffix].freeze
      public_constant :KEYS

      # Reads the keywords passed to the macro.
      # @param keywords [Hash{Symbol => Object}] The keywords.
      # @raise [ArgumentError] Like Ruby, for a keyword the macro does not know.
      # @raise [TypeError] For a value of the wrong type.
      # @return [ActiveRecord::Bitwise::Options]
      sig { params(keywords: T::Hash[Symbol, Value]).returns(Options) }
      def self.parse(keywords)
        unknown = keywords.keys - KEYS
        unless unknown.empty?
          raise ArgumentError, "unknown keyword#{'s' if unknown.size > 1}: #{unknown.map(&:inspect).join(', ')}"
        end

        new(default: flags(keywords[:default]), prefix: affix(:prefix, keywords[:prefix]),
            suffix: affix(:suffix, keywords[:suffix]))
      end

      # @param value [Object, nil] The value of +default:+.
      # @raise [TypeError] When it is neither nil nor an Array.
      # @return [Array<Symbol, String>, nil]
      sig { params(value: Value).returns(T.nilable(Types::Flags)) }
      def self.flags(value)
        case value
        in (nil | Array) => flags then flags
        else raise TypeError, "Parameter 'default': Expected an Array of flags or nil, got #{value.class}"
        end
      end

      # @param option [Symbol] The option name.
      # @param value [Object, nil] The value of the option.
      # @raise [TypeError] When it is not a name, a boolean or nil.
      # @return [Symbol, String, Boolean, nil]
      sig { params(option: Symbol, value: Value).returns(Affix) }
      def self.affix(option, value)
        case value
        in (nil | true | false | Symbol | String) => affix then affix
        else raise TypeError, "Parameter '#{option}': Expected a name, true or nil, got #{value.class}"
        end
      end

      # The default values for new records (must be present in the mapping).
      # @return [Array<Symbol, String>, nil]
      sig { returns(T.nilable(Types::Flags)) }
      attr_reader :default

      # The prefix for the generated method names.
      # @return [Symbol, String, Boolean, nil]
      sig { returns(Affix) }
      attr_reader :prefix

      # The suffix for the generated method names.
      # @return [Symbol, String, Boolean, nil]
      sig { returns(Affix) }
      attr_reader :suffix

      # @param default [Array<Symbol, String>, nil] The default values for new records.
      # @param prefix [Symbol, String, Boolean, nil] The prefix for the generated method names.
      # @param suffix [Symbol, String, Boolean, nil] The suffix for the generated method names.
      sig { params(default: T.nilable(Types::Flags), prefix: Affix, suffix: Affix).void }
      def initialize(default:, prefix:, suffix:)
        @default = default
        @prefix = prefix
        @suffix = suffix
      end
    end
  end
end
