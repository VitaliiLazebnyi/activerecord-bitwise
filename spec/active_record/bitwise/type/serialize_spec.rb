# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Type, '#serialize' do
  subject(:type) { described_class.new(:roles, { admin: 0, editor: 1, author: 2, subscriber: 3 }, nil) }

  context 'with nil' do
    it 'returns nil' do
      expect(type.serialize(nil)).to be_nil
    end
  end

  context 'with an Integer' do
    [0, 5, -5, (2**63) - 1, -(2**63)].each do |bitmask|
      it "passes #{bitmask} through untouched" do
        expect(type.serialize(bitmask)).to eq(bitmask)
      end
    end
  end

  # SQLite would store an out-of-range Integer as a lossy REAL, other adapters fail late and differently,
  # so the type refuses everything beyond a signed 64-bit column, like ActiveModel's own Integer type.
  context 'with an Integer outside the signed 64-bit range' do
    [2**63, 2**64, 2**70, -(2**63) - 1].each do |bitmask|
      it "raises ActiveModel::RangeError for #{bitmask}" do
        message = "#{bitmask} is out of range for column roles: it must fit a signed 64-bit integer"

        expect { type.serialize(bitmask) }.to raise_error(ActiveModel::RangeError, message)
      end
    end

    it 'raises for flags whose raw bitmask marker is out of range' do
      expect { type.serialize(with_raw_marker([:admin], 2**70)) }
        .to raise_error(ActiveModel::RangeError, /out of range for column roles/)
    end
  end

  context 'with flags' do
    it 'returns 0 for an empty array' do
      expect(type.serialize([])).to eq(0)
    end

    it 'sets the bit of a single flag' do
      expect(type.serialize([:subscriber])).to eq(0b1000)
    end

    it 'ORs the bits of several flags' do
      expect(type.serialize(%i[admin subscriber])).to eq(0b1001)
    end

    it 'accepts Strings and Symbols interchangeably' do
      expect(type.serialize(['author', :admin])).to eq(0b101)
    end

    it 'ignores unknown flags' do
      expect(type.serialize([:admin, 'nope'])).to eq(1)
    end

    it 'ignores nil and empty strings' do
      expect(type.serialize([nil, '', :admin])).to eq(1)
    end

    it 'is idempotent for duplicates' do
      expect(type.serialize(%i[admin admin])).to eq(1)
    end

    it 'accepts a single Symbol' do
      expect(type.serialize(:author)).to eq(0b100)
    end

    it 'accepts a single String' do
      expect(type.serialize('author')).to eq(0b100)
    end

    it 'supports the highest bit position (62) without overflow' do
      wide = described_class.new(:wide, { top: 62, bottom: 0 }, nil)

      expect(wide.serialize(%i[top bottom])).to eq((1 << 62) | 1)
    end
  end

  context 'with an array carrying unmapped bits' do
    it 'keeps the unmapped bits and replaces the mapped ones with the flags' do
      marked = with_raw_marker([:admin], 0b1_0000_0110)

      expect(type.serialize(marked)).to eq(0b1_0000_0001)
    end

    it 'keeps unmapped bits when no flag is set' do
      marked = with_raw_marker([], 0b1_0000_0110)

      expect(type.serialize(marked)).to eq(0b1_0000_0000)
    end

    it 'reads a numeric-string marker as an Integer' do
      expect(type.serialize(with_raw_marker([], '256'))).to eq(256)
    end

    it 'treats a marker that is not a number as zero' do
      expect(type.serialize(with_raw_marker([:admin], Object.new))).to eq(1)
    end

    it 'treats a numeric marker that is not an Integer like its integer value' do
      expect(type.serialize(with_raw_marker([:admin], Rational(16)))).to eq(0b1_0001)
    end
  end
end
