# typed: false
# frozen_string_literal: true

# Builds flag arrays carrying the gem's internal "raw bitmask" marker, which the
# getter attaches to every array it returns. Used to model markers that a public
# call cannot produce (for example a marker that is not an Integer).
module RawMarker
  # @param flags [Array<Symbol, String>] the visible flags
  # @param marker [Object] the raw bitmask marker to attach
  # @return [Array<Symbol, String>] an unfrozen copy of +flags+ carrying +marker+
  def with_raw_marker(flags, marker)
    stamped = flags.dup
    stamped.instance_variable_set(:@_bitwise_raw_value, marker)
    stamped
  end
end
