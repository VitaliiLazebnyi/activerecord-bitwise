# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Layout do
  subject(:layout) { described_class.new(:roles, { admin: 0, editor: 1, author: 4 }) }

  describe '#initialize' do
    it 'combines the positions into the known mask' do
      expect(layout.known_mask).to eq(0b10011)
    end

    it 'counts a position shared by two names once' do
      expect(described_class.new(:roles, { a: 0, b: 0 }).known_mask).to eq(1)
    end

    it 'lists the names as Strings' do
      expect(layout.names).to eq(%w[admin editor author])
    end

    it 'freezes the names' do
      expect(layout.names).to be_frozen
    end
  end

  describe '#flags' do
    it 'turns names into symbols for mapped flags and keeps others as Strings' do
      expect(layout.flags(['admin', :editor, 'ghost'])).to eq([:admin, :editor, 'ghost'])
    end

    it 'drops nil and empty entries' do
      expect(layout.flags([nil, '', :admin])).to eq([:admin])
    end

    it 'removes duplicates' do
      expect(layout.flags(['admin', :admin, 'x', :x])).to eq([:admin, 'x'])
    end

    it 'returns a frozen array' do
      expect(layout.flags([:admin])).to be_frozen
    end

    it 'carries the raw marker of the value' do
      expect(ActiveRecord::Bitwise::RawMask.read(layout.flags(ActiveRecord::Bitwise::RawMask.stamp([:admin], 77))))
        .to eq(77)
    end

    it 'does not modify the value' do
      value = ['admin']
      layout.flags(value)

      expect(value).to eq(['admin'])
    end

    it 'refuses more than the maximum number of entries' do
      expect { layout.flags(Array.new(ActiveRecord::Bitwise::MAX_ARRAY_SIZE + 1, :admin)) }
        .to raise_error(ArgumentError, /cannot exceed/)
    end
  end

  describe '#merge' do
    it 'replaces the known bits and keeps the unknown ones of the raw marker' do
      stamped = ActiveRecord::Bitwise::RawMask.stamp([:admin], 0b101111)

      expect(layout.merge(stamped)).to eq(0b101101)
    end

    it 'is the mask of an unstamped value' do
      expect(layout.merge([:editor])).to eq(2)
    end
  end
end
