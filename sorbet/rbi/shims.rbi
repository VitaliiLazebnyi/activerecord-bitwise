# typed: strong

module ActiveModel
  class EachValidator
    sig { params(options: T::Hash[Symbol, T.untyped]).void }
    def initialize(options); end

    sig { params(record: T.untyped, attribute: Symbol, value: T.untyped).void }
    def validate_each(record, attribute, value); end
  end
end

module ActiveRecord
  class Base
    sig { returns(T::Class[T.anything]) }
    def class; end
  end

  class Relation
    sig { returns(T::Class[T.anything]) }
    def klass; end
  end

  module QueryMethods
    class WhereChain
    end
  end

  module Type
    class Value
      sig { params(value: T.untyped).returns(T.untyped) }
      def cast(value); end

      sig { params(value: T.untyped).returns(T.untyped) }
      def deserialize(value); end

      sig { params(value: T.untyped).returns(T.untyped) }
      def serialize(value); end
    end
  end
end

module ActiveSupport
  sig { params(name: Symbol, options: T.untyped, block: T.untyped).void }
  def self.on_load(name, options = nil, &block); end
end

module Arel
  sig { params(sql: String).returns(T.untyped) }
  def self.sql(sql); end
end
