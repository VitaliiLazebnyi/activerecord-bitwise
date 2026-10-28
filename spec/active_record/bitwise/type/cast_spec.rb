# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Type, '#cast' do
  subject(:type) { described_class.new(:roles, { admin: 0, editor: 1, author: 2, subscriber: 3 }, nil) }

  context 'with nil' do
    it 'returns nil' do
      expect(type.cast(nil)).to be_nil
    end
  end

  context 'with an Integer bitmask' do
    {
      0 => [],
      1 => [:admin],
      0b1000 => [:subscriber],
      0b0101 => %i[admin author],
      0b1111 => %i[admin editor author subscriber],
      0b1_0000_0000 => [],
      0b1_0000_0101 => %i[admin author],
      -1 => %i[admin editor author subscriber]
    }.each do |bitmask, expected_flags|
      it "decodes #{bitmask} into #{expected_flags.inspect}" do
        expect(type.cast(bitmask)).to eq(expected_flags)
      end
    end

    it 'returns a frozen array' do
      expect(type.cast(0b101)).to be_frozen
    end

    it 'keeps unmapped bits so that serializing restores the full bitmask' do
      expect(type.serialize(type.cast(0b1_0000_1101))).to eq(0b1_0000_1101)
    end
  end

  context 'with a String' do
    it 'treats a bare numeric string as a bitmask' do
      expect(type.cast('5')).to eq(%i[admin author])
    end

    it 'treats a mapped name as a flag instead of a bitmask' do
      expect(type.cast('admin')).to eq([:admin])
    end

    it 'keeps an unmapped name as a String' do
      expect(type.cast('hacker')).to eq(['hacker'])
    end

    it 'does not treat a negative numeric string as a bitmask' do
      expect(type.cast('-1')).to eq(['-1'])
    end

    it 'does not treat a numeric string with whitespace as a bitmask' do
      expect(type.cast(' 5')).to eq([' 5'])
    end

    it 'treats a numeric string that is also a mapped key as a flag' do
      numeric_key_type = described_class.new(:roles, { '5': 3 }, nil)

      expect(numeric_key_type.cast('5')).to eq([:'5'])
    end
  end

  context 'with a single Symbol' do
    it 'wraps it into an array' do
      expect(type.cast(:author)).to eq([:author])
    end
  end

  context 'with an Array of flag names' do
    it 'symbolizes mapped names and keeps unmapped names as Strings' do
      expect(type.cast(['admin', :author, 'nope'])).to eq([:admin, :author, 'nope'])
    end

    it 'returns an empty array for an empty array' do
      expect(type.cast([])).to eq([])
    end

    it 'drops nil and empty strings' do
      expect(type.cast([nil, '', 'admin'])).to eq([:admin])
    end

    it 'keeps other falsy-looking values as names' do
      expect(type.cast([0, false])).to eq(%w[0 false])
    end

    it 'keeps Integers inside an array as names, not bitmasks' do
      expect(type.cast([5])).to eq(['5'])
    end

    it 'de-duplicates by string form, keeping the first occurrence' do
      expect(type.cast([:admin, 'admin', :admin])).to eq([:admin])
    end

    it 'preserves the given order' do
      expect(type.cast(%i[author admin])).to eq(%i[author admin])
    end

    it 'returns a frozen array' do
      expect(type.cast([:admin])).to be_frozen
    end

    it 'does not freeze or modify the given array' do
      input = [:admin]
      type.cast(input)

      expect(input).not_to be_frozen
    end
  end

  context 'with an Array near the size limit' do
    it 'accepts 99 elements' do
      expect(type.cast(Array.new(99) { |i| "v#{i}" }).size).to eq(99)
    end

    it 'accepts exactly 100 elements' do
      expect(type.cast(Array.new(100) { |i| "v#{i}" }).size).to eq(100)
    end

    it 'rejects 101 elements' do
      expect { type.cast(Array.new(101) { |i| "v#{i}" }) }
        .to raise_error(ArgumentError, 'Array size cannot exceed 100')
    end

    it 'does not count nil and empty strings toward the limit' do
      padded = Array.new(100) { |i| "v#{i}" } + [nil, '']

      expect(type.cast(padded).size).to eq(100)
    end

    it 'counts duplicates toward the limit before de-duplicating' do
      expect { type.cast(Array.new(101) { :admin }) }
        .to raise_error(ArgumentError, 'Array size cannot exceed 100')
    end
  end

  context 'with a value that cannot become a flag array' do
    [{ a: 1 }, true, false].each do |uncastable|
      it "raises for #{uncastable.inspect} naming the value and the column" do
        expect { type.cast(uncastable) }
          .to raise_error(ArgumentError, "cannot cast #{uncastable.inspect} to a bitwise flag array for column roles")
      end
    end

    it 'turns a Float into an unknown flag name' do
      expect(type.cast(1.5)).to eq(['1.5'])
    end
  end

  context 'with an Array that carries a raw bitmask marker' do
    let(:stamped) { type.cast(0b11) }

    it 'returns an already stamped frozen array as the very same object' do
      expect(type.cast(stamped)).to equal(stamped)
    end

    it 'keeps the unmapped bits of an unfrozen stamped array' do
      marked = with_raw_marker([:admin], 0b1_0001)

      expect(type.serialize(type.cast(marked))).to eq(0b1_0001)
    end

    it 'does not return an unfrozen stamped array as the same object' do
      marked = with_raw_marker([:admin], 1)

      expect(type.cast(marked)).not_to equal(marked)
    end

    it 'does not return a frozen unstamped array as the same object' do
      frozen = [:admin].freeze

      expect(type.cast(frozen)).not_to equal(frozen)
    end

    it 'does not stamp a marker onto a plain array' do
      expect(type.serialize(type.cast([:admin]))).to eq(1)
    end
  end

  context 'with a numeric string of several digits' do
    it 'treats it as a bitmask' do
      expect(type.cast('12')).to eq(%i[author subscriber])
    end
  end

  context 'with a numeric String subclass' do
    it 'treats it as a bitmask' do
      expect(type.cast(Class.new(String).new('5'))).to eq(%i[admin author])
    end
  end

  context 'with a Hash subclass' do
    it 'raises ArgumentError like a plain Hash' do
      indifferent = ActiveSupport::HashWithIndifferentAccess.new(a: 1)

      expect { type.cast(indifferent) }.to raise_error(
        ArgumentError, "cannot cast #{indifferent} to a bitwise flag array for column roles"
      )
    end
  end
end
