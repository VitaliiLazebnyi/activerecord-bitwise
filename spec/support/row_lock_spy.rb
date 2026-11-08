# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# SQLite ignores FOR UPDATE, so whether a query asks for a row lock cannot be seen in its SQL
# on the default test database. This records the arguments of every +lock+ call made on
# relations built through +model.where+ instead (the lock itself still runs).
module RowLockSpy
  extend T::Sig
  extend T::Helpers

  # The spy is set up with the mocks of the example it is included into.
  requires_ancestor { RSpec::Mocks::ExampleMethods }

  # @param model [Class] the ActiveRecord model to observe
  # @return [Array<Array>] a live list: one entry (the lock arguments) per +lock+ call
  sig { params(model: T.class_of(ActiveRecord::Base)).returns(T::Array[T::Array[T.anything]]) }
  def track_row_locks(model)
    locks = T.let([], T::Array[T::Array[T.anything]])
    allow(model).to(
      receive(:where).and_wrap_original do |original, *conditions|
        spy_on(original.call(*conditions), locks)
      end
    )
    locks
  end

  private

  # Records the arguments of every +lock+ call on +relation+ in +locks+.
  # @param relation [ActiveRecord::Relation]
  # @param locks [Array<Array>]
  # @return [ActiveRecord::Relation] the relation
  sig do
    params(relation: ActiveRecord::Relation, locks: T::Array[T::Array[T.anything]]).returns(ActiveRecord::Relation)
  end
  def spy_on(relation, locks)
    allow(relation).to(
      receive(:lock).and_wrap_original do |lock, *arguments|
        locks << arguments
        lock.call(*arguments)
      end
    )
    relation
  end
end
