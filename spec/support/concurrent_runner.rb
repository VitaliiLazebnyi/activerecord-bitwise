# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Runs blocks in parallel threads that are all released at the same moment, so that the
# examples do not depend on timing: every task is parked on a start gate until all threads
# are ready, and the caller only continues once every thread has finished.
module ConcurrentRunner
  extend T::Sig

  module_function

  # Runs every task in its own thread, each with its own database connection.
  # @param tasks [Array<Proc>] the work to run concurrently
  # @return [void]
  # @raise [StandardError] the first error raised by any task
  sig { params(tasks: T::Array[T.proc.void]).void }
  def run_concurrently(tasks)
    gate = StartGate.new(tasks.size)
    threads = tasks.map { |task| gate.park(task) }
    gate.open
    threads.each(&:join)
  end

  # Runs +block+ in a new thread and returns its value.
  # @yield the work to run in the other thread
  # @return [Object] the value of the block
  # @raise [StandardError] the error raised by the block
  sig { params(block: T.proc.returns(Object)).returns(Object) }
  def in_another_thread(&block)
    Thread.new(&block).value
  end

  # The gate the threads of {ConcurrentRunner.run_concurrently} wait on.
  class StartGate
    extend T::Sig

    # @param size [Integer] how many threads the gate releases
    sig { params(size: Integer).void }
    def initialize(size)
      @size = size
      # Holds one announcement per parked thread.
      @ready = T.let(Thread::SizedQueue.new(size), Thread::SizedQueue)
      # Closed to release the threads: popping a closed, empty queue returns at once.
      @start = T.let(Thread::Queue.new, Thread::Queue)
    end

    # Starts a thread that announces itself, waits until the gate opens, then runs +task+ with its own
    # database connection.
    # @param task [Proc]
    # @return [Thread]
    sig { params(task: T.proc.void).returns(Thread) }
    def park(task)
      Thread.new do
        @ready << :ready
        @start.pop
        ActiveRecord::Base.connection_pool.with_connection { task.call }
      end
    end

    # Waits until every thread is parked, then releases them all.
    # @return [void]
    sig { void }
    def open
      @size.times { @ready.pop }
      @start.close
    end
  end
end
