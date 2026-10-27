# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#remove_role!' do
  include_context 'with a user model'

  let(:record) { model.create!(roles: %i[admin author]) }

  context 'with a persisted record' do
    it 'removes the flag in the database' do
      record.remove_role!(:author)

      expect(raw_value(record)).to eq(1)
    end

    it 'updates the in-memory flags' do
      record.remove_role!(:author)

      expect(record.roles).to eq([:admin])
    end

    it 'removes several flags at once' do
      record.remove_role!(:admin, :author)

      expect(record.roles).to eq([])
    end

    it 'does nothing for a flag that is not set' do
      record.remove_role!(:subscriber)

      expect(raw_value(record)).to eq(0b101)
    end

    it 'ignores unknown values' do
      record.remove_role!(:bogus, :admin)

      expect(raw_value(record)).to eq(0b100)
    end

    it 'does not leave the record with unsaved changes' do
      record.remove_role!(:author)

      expect(record.changed?).to be(false)
    end

    it 'is also available under the plural name' do
      record.remove_roles!(:author)

      expect(record.roles).to eq([:admin])
    end
  end

  context 'with unmapped bits stored in the database' do
    it 'keeps them' do
      plant_raw_value(record, 0b1_0000_0101)
      record.remove_role!(:admin)

      expect(raw_value(record)).to eq(0b1_0000_0100)
    end
  end

  context 'with a NULL column' do
    it 'ends up with no flags' do
      plant_raw_value(record, nil)
      record.remove_role!(:admin)

      expect(raw_value(record)).to eq(0)
    end
  end

  context 'with a new record' do
    it 'raises ActiveRecordError telling to save first' do
      expect { model.new.remove_role!(:admin) }.to raise_error(
        ActiveRecord::ActiveRecordError, 'cannot atomically remove roles on a new record; save the record first'
      )
    end
  end

  context 'when the record lacks dirty tracking support' do
    it 'still applies the change' do
      allow(record).to receive(:respond_to?).and_call_original
      allow(record).to receive(:respond_to?).with(:clear_attribute_changes).and_return(false)
      record.remove_role!(:author)

      expect(record.roles).to eq([:admin])
    end
  end

  context 'with a column whose name is already singular' do
    it 'removes the flag' do
      singular = build_model('singular_models') { bitwise :status, { active: 0, archived: 1 } }
      stored = singular.create!(status: %i[active archived])
      stored.remove_status!(:active)

      expect(stored.reload.status).to eq([:archived])
    end
  end

  context 'with an uncountable column name' do
    it 'removes the flag' do
      fish = build_model('singular_models') { bitwise :fish, { salmon: 0 } }.create!(fish: [:salmon])
      fish.remove_fish!(:salmon)

      expect(fish.reload.fish).to eq([])
    end
  end
end
