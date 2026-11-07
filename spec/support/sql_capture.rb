# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Records the SQL statements ActiveRecord executes while a block runs.
module SqlCapture
  extend T::Sig
  extend T::Helpers

  # The helpers call Kernel#lambda.
  requires_ancestor { Kernel }

  IGNORED_EVENT_NAMES = %w[SCHEMA TRANSACTION].freeze
  public_constant :IGNORED_EVENT_NAMES

  module_function

  # @yield the code whose statements are recorded
  # @return [Array<String>] the statements, in execution order (schema lookups and
  #   transaction control are left out)
  sig { params(block: T.proc.void).returns(T::Array[String]) }
  def capture_sql(&block)
    capture_sql_events(block).map(&:first)
  end

  # Like {#capture_sql}, but records for every statement whether a transaction was open
  # on +connection+ at the time.
  # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  # @yield the code whose statements are recorded
  # @return [Array<Array(String, Boolean)>] pairs of statement and "transaction open?"
  sig do
    params(connection: ActiveRecord::ConnectionAdapters::AbstractAdapter, block: T.proc.void)
      .returns(T::Array[[String, T::Boolean]])
  end
  def capture_sql_with_transaction_state(connection, &block)
    capture_sql_events(block, connection)
  end

  # The statements executed by +block+, each with whether a transaction was open on +connection+.
  # @param block [Proc]
  # @param connection [ActiveRecord::ConnectionAdapters::AbstractAdapter]
  # @return [Array<Array(String, Boolean)>]
  sig do
    params(block: T.proc.void, connection: ActiveRecord::ConnectionAdapters::AbstractAdapter)
      .returns(T::Array[[String, T::Boolean]])
  end
  def capture_sql_events(block, connection = ActiveRecord::Base.connection)
    statements = T.let([], T::Array[[String, T::Boolean]])
    subscriber =
      lambda do |*_args, payload|
        statements << [payload[:sql], connection.transaction_open?] if IGNORED_EVENT_NAMES.exclude?(payload[:name])
      end
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record', &block)
    statements
  end
end
