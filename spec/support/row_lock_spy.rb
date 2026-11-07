# typed: false
# frozen_string_literal: true

# SQLite ignores FOR UPDATE, so whether a query asks for a row lock cannot be seen in its SQL
# on the default test database. This records the arguments of every +lock+ call made on
# relations built through +model.where+ instead (the lock itself still runs).
module RowLockSpy
  # @param model [Class] the ActiveRecord model to observe
  # @return [Array<Array>] a live list: one entry (the lock arguments) per +lock+ call
  def track_row_locks(model)
    locks = []
    allow(model).to receive(:where).and_wrap_original do |original, *conditions|
      original.call(*conditions).tap do |relation|
        allow(relation).to receive(:lock).and_wrap_original do |lock, *arguments|
          locks << arguments
          lock.call(*arguments)
        end
      end
    end
    locks
  end
end
