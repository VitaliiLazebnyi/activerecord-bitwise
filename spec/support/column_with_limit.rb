# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# A database column that reports another byte limit than the real one, for the adapters that do not offer
# every integer size.
class ColumnWithLimit < SimpleDelegator
  extend T::Sig

  # The byte limit the column reports.
  # @return [Integer, nil]
  sig { returns(T.nilable(Integer)) }
  attr_reader :limit

  # @param column [ActiveRecord::ConnectionAdapters::Column] the real column
  # @param limit [Integer, nil] the byte limit to report instead of the real one
  sig { params(column: ActiveRecord::ConnectionAdapters::Column, limit: T.nilable(Integer)).void }
  def initialize(column, limit)
    super(column)
    @limit = limit
  end
end
