# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::InstanceMethods, '#clear_bitwise_raw_values_cache!' do
  include_context 'with a user model'

  # admin + the unmapped bits 8 and 9
  let(:record) { plant_raw_value(model.create!, 0b11_0000_0001) }

  it 'keeps the flags readable' do
    record.clear_bitwise_raw_values_cache!

    expect(record.roles).to eq([:admin])
  end

  it 'still preserves unmapped bits on the next save, because they are read from the loaded value' do
    record.clear_bitwise_raw_values_cache!
    record.update!(roles: %i[admin author])

    expect(raw_value(record)).to eq(0b11_0000_0101)
  end

  it 'can be called on a record that never touched its bitwise columns' do
    expect { model.new.clear_bitwise_raw_values_cache! }.not_to raise_error
  end

  context 'when the assigned flags carry unmapped bits' do
    it 'rebuilds the cache from them' do
      record.roles = with_raw_marker([:admin], 0b1_0000_0001)
      record.clear_bitwise_raw_values_cache!
      record.update!(roles: [:editor])

      expect(raw_value(record)).to eq(0b1_0000_0010)
    end
  end
end
