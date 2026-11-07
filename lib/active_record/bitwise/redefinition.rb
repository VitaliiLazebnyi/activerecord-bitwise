# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Lets a column that is declared again on the same class replace its generated methods. Ruby warns
    # ("method redefined") when a method is defined over one of the same owner; removing the old
    # definition first gives the same result without the warning.
    module Redefinition
      extend T::Sig

      # Removes the method +name+ from +owner+ when +owner+ itself defines it (inherited methods stay).
      # @param owner [Module] The singleton class the method is about to be defined on.
      # @param name [String, Symbol] The method name.
      # @return [void]
      sig { params(owner: T::Module[T.anything], name: T.any(String, Symbol)).void }
      def self.release(owner, name)
        owner.remove_method(name) if owner.method_defined?(name, false) || owner.private_method_defined?(name, false)
      end
    end
  end
end
