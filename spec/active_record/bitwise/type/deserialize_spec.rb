# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Type, '#deserialize' do
  subject(:type) { described_class.new(:roles, { admin: 0, editor: 1, author: 2, subscriber: 3 }, nil) }

  context 'with nil' do
    it 'returns an empty array' do
      expect(type.deserialize(nil)).to eq([])
    end

    it 'returns a frozen array' do
      expect(type.deserialize(nil)).to be_frozen
    end

    it 'returns an array that serializes to zero' do
      expect(type.serialize(type.deserialize(nil))).to eq(0)
    end

    it 'ignores the configured default' do
      defaulted = described_class.new(:roles, { admin: 0 }, [:admin])

      expect(defaulted.deserialize(nil)).to eq([])
    end
  end

  context 'with an Integer bitmask' do
    {
      0 => [],
      1 => [:admin],
      0b0110 => %i[editor author],
      0b1111 => %i[admin editor author subscriber]
    }.each do |bitmask, expected_flags|
      it "maps #{bitmask} to #{expected_flags.inspect}" do
        expect(type.deserialize(bitmask)).to eq(expected_flags)
      end
    end

    it 'hides unmapped bits from the flags' do
      expect(type.deserialize(0b1_0000_0001)).to eq([:admin])
    end

    it 'keeps unmapped bits for a later serialize' do
      expect(type.serialize(type.deserialize(0b1_0000_0001))).to eq(0b1_0000_0001)
    end

    it 'returns a frozen array' do
      expect(type.deserialize(1)).to be_frozen
    end

    it 'lists flags in mapping order, not in bit order' do
      reversed = described_class.new(:roles, { third: 2, first: 0 }, nil)

      expect(reversed.deserialize(0b101)).to eq(%i[third first])
    end

    it 'supports the highest bit position (62)' do
      wide = described_class.new(:wide, { top: 62, bottom: 0 }, nil)

      expect(wide.deserialize((1 << 62) | 1)).to eq(%i[top bottom])
    end
  end

  context 'with a numeric String (raw value read from an adapter)' do
    it 'decodes the number as a bitmask' do
      expect(type.deserialize('6')).to eq(%i[editor author])
    end

    it 'keeps unmapped bits for a later serialize' do
      expect(type.serialize(type.deserialize('256'))).to eq(256)
    end
  end

  context 'with an Array' do
    it 'returns the same flags' do
      expect(type.deserialize(%i[admin author])).to eq(%i[admin author])
    end

    it 'returns a frozen array' do
      expect(type.deserialize([:admin])).to be_frozen
    end

    it 'derives the raw bitmask from the flags' do
      expect(type.serialize(type.deserialize(%i[admin author]))).to eq(0b101)
    end

    it 'keeps the raw bitmask carried by a stamped array' do
      stamped = type.cast(0b1_0000_0001)

      expect(type.serialize(type.deserialize(stamped))).to eq(0b1_0000_0001)
    end

    it 'keeps unknown names as Strings' do
      expect(type.deserialize([:admin, 'bogus'])).to eq([:admin, 'bogus'])
    end
  end

  context 'when called re-entrantly while decoding' do
    it 'allows one level of nesting' do
      expect(type.deserialize(ReentrantBitmask.new(type, 1))).to eq([:admin])
    end

    it 'raises on the second level of nesting with a descriptive message' do
      expect { type.deserialize(ReentrantBitmask.new(type, 2)) }
        .to raise_error(ActiveRecord::Bitwise::Error, 'System recursion limit exceeded in deserialize')
    end
  end

  context 'when called repeatedly' do
    it 'does not leak recursion depth between successful calls' do
      3.times { type.deserialize(1) }

      expect(type.deserialize(1)).to eq([:admin])
    end

    context 'when a recursion error happened earlier' do
      before { capture_error { type.deserialize(ReentrantBitmask.new(type, 5)) } }

      it 'does not leak recursion depth' do
        expect(Array.new(3) { type.deserialize(1) }).to eq([[:admin]] * 3)
      end
    end
  end

  context 'with nil (shared result)' do
    it 'returns the same frozen array every time' do
      expect(type.deserialize(nil)).to equal(type.deserialize(nil))
    end

    it 'carries the empty raw bitmask' do
      expect(raw_marker_of(type.deserialize(nil))).to eq(0)
    end

    it 'does not leak unmapped bit 0 into the serialized value' do
      second_only = described_class.new(:flags, { second: 1 }, nil)

      expect(second_only.serialize(second_only.deserialize(nil))).to eq(0)
    end
  end

  context 'with an unstamped Array' do
    it 'carries the bitmask of its flags' do
      expect(raw_marker_of(type.deserialize(%i[admin author]))).to eq(0b101)
    end
  end

  context 'with a stamped Array' do
    it 'keeps its raw bitmask' do
      stamped = with_raw_marker(%i[admin], 0b1_0000_0110)

      expect(raw_marker_of(type.deserialize(stamped))).to eq(0b1_0000_0110)
    end
  end

  context 'with an Array subclass' do
    it 'returns its flags like a plain Array' do
      expect(type.deserialize(Class.new(Array)[:admin])).to eq([:admin])
    end
  end
end
