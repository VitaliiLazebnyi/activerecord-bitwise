# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Type do
  subject(:type) { described_class.new(:roles, mapping, default) }

  let(:mapping) { { admin: 0, editor: 1, author: 2, subscriber: 3 } }
  let(:default) { nil }

  describe '#column_name' do
    it 'returns the column name as given' do
      expect(type.column_name).to eq(:roles)
    end

    it 'converts a String column name to a Symbol' do
      expect(described_class.new('flags', mapping, nil).column_name).to eq(:flags)
    end
  end

  describe '#mapping' do
    it 'returns the key to bit position mapping' do
      expect(type.mapping).to eq(admin: 0, editor: 1, author: 2, subscriber: 3)
    end
  end

  describe '#default' do
    it 'is an empty array when no default is given' do
      expect(type.default).to eq([])
    end

    context 'with a default' do
      let(:default) { [:admin] }

      it 'returns the given default' do
        expect(type.default).to eq([:admin])
      end
    end
  end

  describe '#known_mask' do
    it 'has one bit per mapped position' do
      expect(type.known_mask).to eq(0b1111)
    end

    context 'with sparse positions' do
      let(:mapping) { { bottom: 0, top: 62 } }

      it 'has exactly the mapped bits set' do
        expect(type.known_mask).to eq((1 << 62) | 1)
      end
    end
  end

  describe '#mapping_strings' do
    it 'lists the mapping keys as Strings in mapping order' do
      expect(type.mapping_strings).to eq(%w[admin editor author subscriber])
    end

    it 'is frozen' do
      expect(type.mapping_strings).to be_frozen
    end
  end
end
