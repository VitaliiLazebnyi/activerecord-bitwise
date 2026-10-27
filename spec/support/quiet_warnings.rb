# typed: false
# frozen_string_literal: true

# Runs code that is known to make Ruby emit "method redefined" warnings, so that the
# warning guard (see WarningGuard) does not fail an example that deliberately does it.
module QuietWarnings
  # @yield the code whose Ruby warnings are silenced
  # @return [Object] the block's result
  def without_ruby_warnings
    verbose = $VERBOSE
    $VERBOSE = nil
    yield
  ensure
    $VERBOSE = verbose
  end
end
