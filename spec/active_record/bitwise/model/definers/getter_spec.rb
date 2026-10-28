# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model::Definers::Getter, '.stamped' do
  let(:type) { ActiveRecord::Bitwise::Type.new(:roles, { admin: 0, editor: 1 }, nil) }
  let(:marker_name) { :@_bitwise_raw_value }
  let(:marker_of) { ->(array) { array.instance_variable_get(marker_name) } }
  let(:stamped_array) { ->(raw, frozen: false) { with_raw_marker([:admin], raw).tap { |array| frozen && array.freeze } } }

  context 'with a value that is not an Array' do
    it 'returns it unchanged' do
      expect(described_class.stamped(type, 5, 1)).to eq(5)
    end
  end

  context 'with nil' do
    it 'returns the shared empty flag array' do
      expect(described_class.stamped(type, nil, 0)).to eq([])
    end

    it 'carries the empty raw bitmask' do
      expect(marker_of.call(described_class.stamped(type, nil, 0))).to eq(0)
    end
  end

  # Decision table: frozen? x stamped? -> is a new frozen array stamped with the given raw bitmask?
  context 'with a frozen array that already carries a marker' do
    it 'returns the very same array' do
      array = stamped_array.call(0b1, frozen: true)

      expect(described_class.stamped(type, array, 0b11)).to equal(array)
    end
  end

  context 'with a frozen array without a marker' do
    let(:result) { described_class.stamped(type, [:admin].freeze, 0b101) }

    it 'stamps a copy with the given raw bitmask' do
      expect(marker_of.call(result)).to eq(0b101)
    end

    it 'keeps the flags' do
      expect(result).to eq([:admin])
    end

    it 'returns a frozen array' do
      expect(result).to be_frozen
    end
  end

  context 'with an unfrozen array that carries a marker' do
    let(:array) { stamped_array.call(0b1) }
    let(:result) { described_class.stamped(type, array, 0b101) }

    it 'replaces the marker with the given raw bitmask' do
      expect(marker_of.call(result)).to eq(0b101)
    end

    it 'returns a frozen copy' do
      expect(result).to be_frozen
    end

    it 'leaves the original array alone' do
      result

      expect(marker_of.call(array)).to eq(0b1)
    end
  end

  context 'with an unfrozen array without a marker' do
    let(:result) { described_class.stamped(type, [:admin], 0b101) }

    it 'stamps it with the given raw bitmask' do
      expect(marker_of.call(result)).to eq(0b101)
    end

    it 'returns a frozen array' do
      expect(result).to be_frozen
    end
  end
end
