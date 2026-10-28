# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::InstanceMethods, '#_bitwise_raw_cache' do
  include_context 'with a user model'

  # admin + the unmapped bit 4
  let(:record) { plant_raw_value(model.create!, 0b1_0001) }

  context 'with a record that never touched its bitwise columns' do
    it 'is empty' do
      expect(model.new._bitwise_raw_cache).to eq({})
    end
  end

  context 'when a column was read' do
    it 'holds the raw bitmask of that column only' do
      record.roles

      expect(record._bitwise_raw_cache).to eq(roles: 0b1_0001)
    end
  end

  context 'when an atomic instance update ran' do
    it 'holds the bitmask stored by the update' do
      record.add_role!(:author)

      expect(record._bitwise_raw_cache).to eq(roles: 0b1_0101)
    end

    it 'holds the bitmask left by a removal' do
      record.remove_role!(:admin)

      expect(record._bitwise_raw_cache).to eq(roles: 0b1_0000)
    end
  end

  context 'when the database changed since the cache was filled' do
    it 'holds the bitmask read back under the row lock' do
      record.roles
      model.where(id: record.id).update_all('roles = 33')
      record.add_role!(:author)

      expect(record._bitwise_raw_cache).to eq(roles: 0b10_0101)
    end
  end

  context 'when nil was assigned' do
    it 'holds zero, so the unmapped bits are dropped' do
      record.roles = nil

      expect(record._bitwise_raw_cache).to eq(roles: 0)
    end
  end

  context 'when an Integer was assigned' do
    it 'holds the assigned bitmask' do
      record.roles = 0b10_0100

      expect(record._bitwise_raw_cache).to eq(roles: 0b10_0100)
    end
  end

  context 'when update_columns ran' do
    it 'holds the bitmask written for a flag array, keeping the unmapped bit' do
      record.update_columns(roles: [:author])

      expect(record._bitwise_raw_cache).to eq(roles: 0b1_0100)
    end

    it 'holds the bitmask written for an Integer' do
      record.update_columns(roles: 3)

      expect(record._bitwise_raw_cache).to eq(roles: 3)
    end

    it 'ignores columns that are not bitwise' do
      record.update_columns(name: 'Ann')

      expect(record._bitwise_raw_cache).to eq({})
    end

    it 'holds the bitmask of every bitwise column written' do
      record.update_columns(roles: [:editor], permissions: [:manage])

      expect(record._bitwise_raw_cache).to eq(roles: 0b1_0010, permissions: 0b10)
    end
  end

  context 'with a duplicate' do
    it 'forgets the unmapped bits of every bitwise column' do
      expect(record.dup._bitwise_raw_cache).to eq(roles: 0, permissions: 0, legacy_roles: 0)
    end
  end

  context 'with clear_bitwise_raw_values_cache!' do
    it 'is an empty Hash stored on the record' do
      record.roles
      record.clear_bitwise_raw_values_cache!

      expect(record.instance_variable_get(:@_bitwise_raw_values)).to eq({})
    end
  end
end
