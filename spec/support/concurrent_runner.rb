# typed: false
# frozen_string_literal: true

# Runs blocks in parallel threads that are all released at the same moment, so that the
# examples do not depend on timing: every task is parked on a start gate until all threads
# are ready, and the caller only continues once every thread has finished.
module ConcurrentRunner
  # Runs every task in its own thread, each with its own database connection.
  # @param tasks [Array<#call>] the work to run concurrently
  # @return [void]
  # @raise [StandardError] the first error raised by any task
  def run_concurrently(*tasks)
    ready = Queue.new
    start = Queue.new
    threads = tasks.map { |task| spawn_parked(task, ready, start) }
    tasks.size.times { ready.pop }
    tasks.size.times { start << :go }
    threads.each(&:join)
  end

  private

  # Starts a thread that announces itself on +ready+, waits on +start+, then runs +task+.
  # @param task [#call]
  # @param ready [Queue]
  # @param start [Queue]
  # @return [Thread]
  def spawn_parked(task, ready, start)
    Thread.new do
      ready << :ready
      start.pop
      ActiveRecord::Base.connection_pool.with_connection { task.call }
    end
  end
end
