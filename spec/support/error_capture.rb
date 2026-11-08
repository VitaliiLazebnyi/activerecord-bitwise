# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Lets an example trigger an expected failure as part of its setup.
module ErrorCapture
  extend T::Sig

  module_function

  # Runs the block and returns the StandardError it raised, or nil.
  # @yield the code that may fail
  # @return [StandardError, nil]
  sig { params(block: T.proc.void).returns(T.nilable(StandardError)) }
  def capture_error(&block)
    yield
    nil
  rescue StandardError => error
    error
  end
end
