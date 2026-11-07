# typed: false
# frozen_string_literal: true

# Lets an example trigger an expected failure as part of its setup.
module ErrorCapture
  # Runs the block and returns the StandardError it raised, or nil.
  # @return [StandardError, nil]
  def capture_error
    yield
    nil
  rescue StandardError => e
    e
  end
end
