# typed: strict
# frozen_string_literal: true

require 'active_record'
require 'active_record/bitwise/bitwise_validator'
require 'active_record/bitwise/conditions'
require 'active_record/bitwise/errors'
require 'active_record/bitwise/model'
require 'active_record/bitwise/relation_extension'
require 'active_record/bitwise/type'
require 'active_record/bitwise/types'
require 'active_record/bitwise/version'
require 'sorbet-runtime'

module ActiveRecord
  # The main namespace for the ActiveRecord::Bitwise gem, which provides capabilities
  # to store multiple boolean or enum values in a single integer column.
  module Bitwise
    extend T::Sig

    # Serializes bitwise values inside a `where`-style conditions hash into their
    # integer bitmask representation (exact-match semantics). Non-bitwise keys and
    # already-integer values pass through untouched.
    # @param klass [Class] The model class owning the bitwise definitions.
    # @param hash [Hash] The conditions hash.
    # @raise [UnknownValueError] When a flag is missing from the mapping.
    # @return [Hash] The (possibly copied) conditions hash.
    sig { params(klass: Types::ModelClass, hash: Types::Params).returns(Types::Params) }
    def self.serialize_conditions(klass, hash)
      Conditions.serialize(klass, hash)
    end
  end
end

ActiveSupport.on_load(:active_record) do
  extend ActiveRecord::Bitwise::Model
  ActiveRecord::Relation.prepend(ActiveRecord::Bitwise::RelationExtension)
  ActiveRecord::QueryMethods::WhereChain.prepend(ActiveRecord::Bitwise::WhereChainExtension)
end
