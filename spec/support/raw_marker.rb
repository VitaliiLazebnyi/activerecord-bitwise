# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Builds flag arrays carrying the gem's internal "raw bitmask" marker, which the
# getter attaches to every array it returns. Used to model markers that a public
# call cannot produce (for example a marker that is not an Integer, or a marker on an object that is not
# an Array).
module RawMarker
  extend T::Sig

  module_function

  # @param flags [Array<Symbol, String>, Object] the visible flags (or any other object to mark)
  # @param marker [Object] the raw bitmask marker to attach
  # @return [Array<Symbol, String>, Object] an unfrozen copy of +flags+ carrying +marker+
  sig do
    type_parameters(:Flags)
      .params(flags: T.all(Object, T.type_parameter(:Flags)), marker: BasicObject)
      .returns(T.all(Object, T.type_parameter(:Flags)))
  end
  def with_raw_marker(flags, marker)
    stamped = flags.dup
    stamped.instance_variable_set(:@_bitwise_raw_value, marker)
    stamped
  end

  # @param flags [Array<Symbol, String>] a flag array
  # @return [Object, nil] the raw bitmask marker attached to +flags+ (nil when there is none)
  sig { params(flags: Object).returns(T.anything) }
  def raw_marker_of(flags)
    flags.instance_variable_get(:@_bitwise_raw_value)
  end
end
