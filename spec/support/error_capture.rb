# typed: true
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Lets an example trigger an expected failure as part of its setup.
module ErrorCapture
  # Runs the block and returns the StandardError it raised, or nil.
  # @return [StandardError, nil]
  def capture_error
    yield
    nil
  rescue StandardError => error
    error
  end
end
