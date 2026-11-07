# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'sorbet-runtime'

# The outdated check (script/outdated.rb).
module Outdated
  # The repository root.
  ROOT = T.let(File.expand_path('../..', __dir__), String)
  public_constant :ROOT

  # The verdicts of the checks: every pinned version against the newest release, and the holds that were used.
  class Report
    extend T::Sig

    # Creates an empty report.
    # @param holds [Hash{String => String}] The newest release each hold keeps out, by label.
    sig { params(holds: T::Hash[String, String]).void }
    def initialize(holds)
      @holds = holds
      @held = T.let(Set.new, T::Set[String])
      @failures = T.let([], T::Array[String])
    end

    # Records the verdict on one pinned dependency.
    # @param label [String] The dependency, e.g. "gem rake" (the key of its hold, if it has one).
    # @param pinned [String] The pinned version (or commit, or digest).
    # @param newest [String] The newest release (or the commit or digest of the pinned tag).
    # @return [void]
    sig { params(label: String, pinned: String, newest: String).void }
    def compare(label, pinned, newest)
      if pinned == newest
        $stdout.puts("current: #{label} #{pinned}")
      elsif @holds[label] == newest
        @held << label
        $stdout.puts("on hold: #{label} #{pinned} -> #{newest}")
      else
        fail_with("OUTDATED (not on the hold list): #{label} #{pinned} -> #{newest}")
      end
    end

    # Records a problem.
    # @param message [String]
    # @return [void]
    sig { params(message: String).void }
    def fail_with(message)
      @failures << message
    end

    # The problems: those recorded, and every hold that kept nothing out (its dependency is at its newest release).
    # @return [Array<String>]
    sig { returns(T::Array[String]) }
    def failures
      stale = @holds.keys.reject { |label| @held.include?(label) }
      @failures + stale.map { |label| "STALE HOLD (no longer outdated): #{label}" }
    end

    # Prints the problems, the holds that are no longer needed among them, and returns the exit status.
    # @return [Integer] 0 when there is no problem.
    sig { returns(Integer) }
    def status
      found = failures
      found.each { |failure| warn(failure) }
      found.empty? ? 0 : 1
    end
  end
end
