# typed: true
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Turns every Ruby warning raised from this project's own code (lib/ and spec/)
# into a test failure. Warnings that originate in third-party gems are ignored.
module WarningGuard
  PROJECT_ROOT = File.expand_path('../..', __dir__)
  OWN_DIRECTORIES = [File.join(PROJECT_ROOT, 'lib'), File.join(PROJECT_ROOT, 'spec')].freeze
  LOCATION = /\A(?<path>[^:\n]+\.rb):\d+/
  COLLECTED = Queue.new
  public_constant :PROJECT_ROOT, :OWN_DIRECTORIES, :LOCATION, :COLLECTED

  # Raised when this project's code emitted a Ruby warning.
  class Failure < StandardError; end

  # Returns and forgets the warnings collected so far.
  # @return [Array<String>]
  def self.drain
    Array.new(COLLECTED.size) { COLLECTED.pop }
  end

  # Whether +message+ names a file inside this project's lib/ or spec/ directory.
  # @param message [String] a Ruby warning message
  # @return [Boolean]
  def self.own?(message)
    match = LOCATION.match(message) or return false
    path = File.expand_path(match[:path])
    OWN_DIRECTORIES.any? { |directory| path.start_with?("#{directory}/") }
  end

  # Records warnings coming from this project, then defers to Ruby's default handling.
  # @param message [String]
  # @return [void]
  def warn(message, ...)
    COLLECTED << message if WarningGuard.own?(message)
    super
  end
end

Warning[:deprecated] = true
Warning[:experimental] = true
Warning.singleton_class.prepend(WarningGuard)
