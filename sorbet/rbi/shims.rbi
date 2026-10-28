# typed: strong

module ActiveModel
  class EachValidator
    sig { params(options: T::Hash[Symbol, T.untyped]).void }
    def initialize(options); end

    sig { params(record: T.untyped, attribute: Symbol, value: T.untyped).void }
    def validate_each(record, attribute, value); end

    sig { returns(T::Hash[Symbol, T.untyped]) }
    def options; end
  end

  module Type
    class Boolean
      sig { params(value: T.untyped).returns(T.untyped) }
      def cast(value); end
    end
  end
end

module ActiveRecord
  class ActiveRecordError < StandardError; end

  class Base
    sig { returns(T::Class[T.anything]) }
    def class; end

    sig { returns(T::Boolean) }
    def new_record?; end

    sig { returns(T.untyped) }
    def id; end

    sig { params(attr_name: T.untyped).returns(T.untyped) }
    def read_attribute(attr_name); end

    sig { params(attr_name: T.untyped, value: T.untyped).returns(T.untyped) }
    def write_attribute(attr_name, value); end

    sig { params(attr_name: T.untyped).returns(T.untyped) }
    def read_attribute_before_type_cast(attr_name); end

    sig { params(attr_names: T.untyped).returns(T.untyped) }
    def clear_attribute_changes(attr_names); end

    sig { returns(T.untyped) }
    def save!; end

    sig { params(attr_name: T.untyped).returns(T.untyped) }
    def attribute_will_change!(attr_name); end
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

  module Nodes
    class Node; end
    class SqlLiteral < String; end
  end
end
