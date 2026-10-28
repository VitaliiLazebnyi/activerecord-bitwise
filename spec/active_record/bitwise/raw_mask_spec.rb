# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::RawMask do
  describe '.integer?' do
    [0, 5, -3, 2**70].each do |value|
      it "is true for the Integer #{value}" do
        expect(described_class.integer?(value)).to be(true)
      end
    end

    [nil, '5', 5.0, [5], :five, Object].each do |value|
      it "is false for #{value.inspect}" do
        expect(described_class.integer?(value)).to be(false)
      end
    end
  end

  describe '.stamped?' do
    it 'is true for an array carrying a raw bitmask' do
      expect(described_class.stamped?(with_raw_marker([:admin], 5))).to be(true)
    end

    it 'is true for a frozen stamped array' do
      expect(described_class.stamped?(with_raw_marker([:admin], 5).freeze)).to be(true)
    end

    it 'is false for a plain array' do
      expect(described_class.stamped?([:admin])).to be(false)
    end

    [nil, 5, 'text'].each do |value|
      it "is false for #{value.inspect}" do
        expect(described_class.stamped?(value)).to be(false)
      end
    end
  end

  describe '.read' do
    it 'returns the raw bitmask of a stamped array' do
      expect(described_class.read(with_raw_marker([], 0b1_0100))).to eq(0b1_0100)
    end
  end

  describe '.stamp' do
    it 'attaches the raw bitmask to the array' do
      expect(raw_marker_of(described_class.stamp([:admin], 9))).to eq(9)
    end

    it 'returns the very array it was given' do
      flags = [:admin]

      expect(described_class.stamp(flags, 9)).to equal(flags)
    end
  end

  describe '.integer' do
    [
      ['12', 12], ['12abc', 12], ['abc', 0], ['', 0], [nil, 0], [7.9, 7], [-4, -4], ['0b11', 0]
    ].each do |value, expected|
      it "converts #{value.inspect} to #{expected}" do
        expect(described_class.integer(value)).to eq(expected)
      end
    end
  end

  describe '.coerce' do
    [
      [5, 5], [-3, -3], [0, 0], ['12', 12], ['7x', 7], [nil, 0], [7.5, 7], [2**70, 2**70]
    ].each do |value, expected|
      it "coerces #{value.inspect} to #{expected}" do
        expect(described_class.coerce(value)).to eq(expected)
      end
    end

    it 'coerces an object that cannot be converted to 0' do
      expect(described_class.coerce(Object.new)).to eq(0)
    end
  end

  describe '.empty' do
    it 'is an empty frozen array' do
      expect(described_class.empty).to be_frozen.and eq([])
    end

    it 'carries the empty raw bitmask' do
      expect(raw_marker_of(described_class.empty)).to eq(0)
    end
  end

  describe '.names' do
    it 'lists the flag names as strings' do
      expect(described_class.names(admin: 0, editor: 1)).to eq(%w[admin editor])
    end

    it 'returns a frozen list' do
      expect(described_class.names(admin: 0)).to be_frozen
    end
  end

  describe '.known_mask' do
    {
      {} => 0,
      { a: 0 } => 0b1,
      { a: 0, b: 3 } => 0b1001,
      { a: 62 } => 1 << 62,
      { a: 1, b: 1 } => 0b10
    }.each do |mapping, expected|
      it "covers #{mapping.inspect} with #{expected}" do
        expect(described_class.known_mask(mapping)).to eq(expected)
      end
    end
  end

  describe '.mask_of' do
    it 'is the raw bitmask of a stamped array' do
      expect(described_class.mask_of(with_raw_marker([:admin], 0b1_0001))).to eq(0b1_0001)
    end

    it 'converts a numeric string marker' do
      expect(described_class.mask_of(with_raw_marker([], '256'))).to eq(256)
    end

    it 'is 0 for an unstamped array' do
      expect(described_class.mask_of([:admin])).to eq(0)
    end

    it 'is 0 for a marker that cannot be converted' do
      expect(described_class.mask_of(with_raw_marker([], Object.new))).to eq(0)
    end
  end

  describe '.extract' do
    it 'is the raw bitmask of a stamped array' do
      expect(described_class.extract(with_raw_marker([:admin], 0b1_0001))).to eq(0b1_0001)
    end

    it 'converts a numeric string marker' do
      expect(described_class.extract(with_raw_marker([], '256'))).to eq(256)
    end

    [
      [[:admin], 0], [5, 5], ['7', 7], [nil, 0]
    ].each do |value, expected|
      it "is #{expected} for the unstamped #{value.inspect}" do
        expect(described_class.extract(value)).to eq(expected)
      end
    end
  end
end
