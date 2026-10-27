# typed: false
# frozen_string_literal: true

# A bitmask-like value whose #to_i calls back into Type#deserialize +levels+ times,
# simulating a value whose coercion re-enters the type.
class ReentrantBitmask
  # @param type [ActiveRecord::Bitwise::Type] the type to re-enter
  # @param levels [Integer] how many nested deserialize calls #to_i makes
  def initialize(type, levels)
    @type = type
    @levels = levels
  end

  # Re-enters the type, then reports the bitmask 1.
  # @return [Integer]
  def to_i
    @type.deserialize(self.class.new(@type, @levels - 1)) if @levels.positive?
    1
  end
end
