# typed: strict
# frozen_string_literal: true

require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    module InstanceMethods
      # Gives the instance-level concerns access to the model class that declared the bitwise columns.
      module ModelAccess
        extend T::Sig
        extend T::Helpers

        requires_ancestor { ActiveRecord::Base }

        # The model class of this record (typed loosely: it carries the macros added by the gem).
        # @return [T.untyped]
        sig { returns(T.untyped) }
        def _bitwise_model
          T.unsafe(self).class
        end
      end
    end
  end
end
