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
      # @param blk [Proc] The guarded work.
      # @raise [Error] When the nesting depth is already at the limit.
      # @return [Object, nil] The block's result.
      sig do
        type_parameters(:Result).params(blk: T.proc.returns(T.type_parameter(:Result)))
                                .returns(T.type_parameter(:Result))
      end
      def self.run(&blk)
        thread = Thread.current
        depth = thread[KEY] || 0
        raise Error, 'System recursion limit exceeded in deserialize' if depth >= LIMIT

        nested(thread, depth, blk)
      end

      # Runs +work+ with the depth of +thread+ raised by one and restores it afterwards.
      # @param thread [Thread] The current thread.
      # @param depth [Integer] The depth before this call.
      # @param work [Proc] The guarded work.
      # @return [Object, nil] The work's result.
      sig do
        type_parameters(:Result).params(thread: Thread, depth: Integer, work: T.proc.returns(T.type_parameter(:Result)))
                                .returns(T.type_parameter(:Result))
      end
      def self.nested(thread, depth, work)
        thread[KEY] = depth + 1
        work.call
      ensure
        thread[KEY] = depth
      end
      private_class_method :nested
    end
  end
end
