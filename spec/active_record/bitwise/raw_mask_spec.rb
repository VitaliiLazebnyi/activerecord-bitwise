# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::RawMask do
  # What String#to_i reads: blanks and a sign, then digits (single underscores allowed between them).
  [
    ['12', 12], ['12abc', 12], ['  7', 7], ["\t\n8", 8], ['-3', -3], ['+4', 4], ['- 5', 0], ['1_000', 1000],
    ['1__0', 1], ['1_', 1], ['0x1f', 0], ['0b11', 0], ['007', 7], ['08', 8], ['1e3', 1], ['', 0], ['abc', 0],
    ['99999999999999999999', 99_999_999_999_999_999_999]
  ].each do |text, integer|
    it "reads #{text.inspect} as #{integer}" do
      expect(described_class.integer(text)).to eq(integer)
    end
  end

  describe '.integer' do
    [[5, 5], [-5, -5], [3.9, 3], [-3.9, -3], [Rational(7, 2), 3], [2**70, 2**70]].each do |number, integer|
      it "reads #{number.inspect} as #{integer}" do
        expect(described_class.integer(number)).to eq(integer)
      end
    end

    it 'reads any object that responds to to_i' do
      duck = double(to_i: 42)
      expect(described_class.integer(duck)).to eq(42)
    end

    it 'raises TypeError for something that cannot be converted' do
      expect { described_class.integer(:admin) }.to raise_error(TypeError, /Symbol/)
    end
  end

  describe '.lenient' do
    [[nil, 0], [:admin, 0], [Object.new, 0], [[1], 0], ['5', 5], ['x', 0], [7, 7], [2.5, 2]].each do |value, integer|
      it "reads #{value.inspect} as #{integer}" do
        expect(described_class.lenient(value)).to eq(integer)
      end
    end
  end

  describe '.mask_of' do
    it 'is the marker of a stamped array' do
      expect(described_class.mask_of(described_class.stamp([:admin], 6))).to eq(6)
    end

    it 'is 0 for an unstamped array' do
      expect(described_class.mask_of([:admin])).to eq(0)
    end

    it 'is 0 for something that is not an array' do
      expect(described_class.mask_of(6)).to eq(0)
    end

    it 'reads a String marker leniently' do
      expect(described_class.mask_of(described_class.stamp([], '9x'))).to eq(9)
    end
  end

  describe '.digits?' do
    %w[0 12 007].each do |text|
      it("accepts #{text.inspect}") { expect(described_class.digits?(text)).to be(true) }
    end

    ['', '-1', '1 ', 'a1', 12, nil, :'1'].each do |value|
      it("rejects #{value.inspect}") { expect(described_class.digits?(value)).to be(false) }
    end
  end

  describe '.carry' do
    it 'copies a truthy marker' do
      source = described_class.stamp([:a], 5)

      expect(described_class.read(described_class.carry([:b], source))).to eq(5)
    end

    it 'leaves the target unstamped when the source has no marker' do
      expect(described_class.stamped?(described_class.carry([:b], [:a]))).to be(false)
    end

    it 'leaves the target unstamped when the marker is falsy' do
      expect(described_class.stamped?(described_class.carry([:b], described_class.stamp([:a], nil)))).to be(false)
    end

    it 'ignores a source that is not an array' do
      expect(described_class.stamped?(described_class.carry([:b], 5))).to be(false)
    end
  end

  describe '.unwrap' do
    it 'is the marker of a stamped array' do
      expect(described_class.unwrap(described_class.stamp([], 3))).to eq(3)
    end

    it 'is the value itself otherwise' do
      expect(described_class.unwrap(:value)).to eq(:value)
    end
  end
end
