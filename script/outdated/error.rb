# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

module Outdated
  # Raised when a check cannot find out the newest release of a dependency.
  class Error < StandardError; end
end
