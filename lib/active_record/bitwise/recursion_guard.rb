# typed: strict
# frozen_string_literal: true

require 'active_record/bitwise/errors'
require 'sorbet-runtime'

module ActiveRecord
  module Bitwise
    # Thread-local nesting limit protecting {Type#deserialize} against runaway recursion.
    # The counter is thread-local (not shared instance state), so it is safe on non-GIL
    # runtimes (JRuby/TruffleRuby) and immune to async exceptions leaking the counter.
    module RecursionGuard
      extend T::Sig

      # Thread-local key of the nesting depth.
      KEY = :ar_bitwise_deserialize_depth
      private_constant :KEY

      # Maximum nested calls before aborting.
      LIMIT = 2
      private_constant :LIMIT

      # Runs the block one nesting level deeper.
      # @param blk [T.proc.returns(T.untyped)] The guarded work.
      # @raise [Error] When the nesting depth is already at the limit.
      # @return [T.untyped] The block's result.
      sig do
        type_parameters(:Result).params(blk: T.proc.returns(T.type_parameter(:Result)))
                                .returns(T.type_parameter(:Result))
      end
      def self.run(&blk) # rubocop:disable Naming/BlockForwarding -- Sorbet's runtime sig check needs the block named
        depth = Thread.current[KEY] || 0
        raise Error, 'System recursion limit exceeded in deserialize' if depth >= LIMIT

        begin
          Thread.current[KEY] = depth + 1
          yield
        ensure
          Thread.current[KEY] = depth
        end
      end
    end
  end
end
