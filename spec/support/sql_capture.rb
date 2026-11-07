# typed: true
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Records the SQL statements ActiveRecord executes while a block runs.
module SqlCapture
  extend T::Helpers

  # The helpers call Kernel#lambda on the example they are included into.
  requires_ancestor { Kernel }

  IGNORED_EVENT_NAMES = %w[SCHEMA TRANSACTION].freeze
  public_constant :IGNORED_EVENT_NAMES

  # @yield the code whose statements are recorded
  # @return [Array<String>] the statements, in execution order (schema lookups and
  #   transaction control are left out)
  def capture_sql(&block)
    statements = []
    subscriber =
      lambda do |*_args, payload|
        statements << payload[:sql] if IGNORED_EVENT_NAMES.exclude?(payload[:name])
      end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &block)
    statements
  end

  # Like {#capture_sql}, but records for every statement whether a transaction was open
  # on +connection+ at the time.
  # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  # @yield the code whose statements are recorded
  # @return [Array<Array(String, Boolean)>] pairs of statement and "transaction open?"
  def capture_sql_with_transaction_state(connection, &block)
    statements = []
    subscriber =
      lambda do |*_args, payload|
        next if IGNORED_EVENT_NAMES.include?(payload[:name])

        statements << [payload[:sql], connection.transaction_open?]
      end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &block)
    statements
  end
end
