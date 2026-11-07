# typed: false
# frozen_string_literal: true

RSpec.describe 'Integer bitmasks outside the signed 64-bit range' do
  include_context 'with a user model'

  let(:too_large) { 2**70 }

  context 'when assigning to a new record' do
    it 'raises ActiveModel::RangeError on save' do
      expect { model.create!(roles: too_large) }
        .to raise_error(ActiveModel::RangeError, /\A#{too_large} is out of range for column roles/)
    end

    it 'stores no row' do
      capture_error { model.create!(roles: too_large) }

      expect(model.count).to eq(0)
    end
  end

  context 'when assigning a numeric String of that size' do
    it 'raises ActiveModel::RangeError on save' do
      expect { model.create!(roles: too_large.to_s) }.to raise_error(ActiveModel::RangeError)
    end
  end

  context 'when assigning to a persisted record' do
    it 'leaves the stored bitmask untouched' do
      record = model.create!(roles: [:admin])
      record.roles = too_large
      capture_error { record.save! }

      expect(raw_value(record)).to eq(1)
    end
  end

  context 'when querying with such a value' do
    it 'matches nothing instead of comparing against a lossy float' do
      model.create!(roles: [:admin])

      expect(model.where(roles: too_large).to_a).to eq([])
    end
  end

  context 'when updating with such a value' do
    it 'raises instead of storing a float' do
      model.create!(roles: [:admin])

      expect { model.update_all(roles: too_large) }.to raise_error(ActiveModel::RangeError)
    end
  end

  # Only a BIGINT column can hold it: the users.roles column is a 4-byte INTEGER on PostgreSQL and MySQL.
  context 'with the largest valid bitmask in a BIGINT column' do
    it 'is stored exactly' do
      wide = build_model('capacity_records') { bitwise :big, { flag: 62 } }
      record = wide.create!(big: (2**63) - 1)

      expect(raw_value(record, :big)).to eq((2**63) - 1)
    end
  end
end
