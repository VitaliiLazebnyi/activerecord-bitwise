# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#admin!' do
  include_context 'with a user model'

  context 'with an unsaved record' do
    it 'saves the record' do
      record = model.new
      record.admin!

      expect(record).to be_persisted
    end

    it 'stores the flag bit' do
      record = model.new
      record.admin!

      expect(raw_value(record)).to eq(1)
    end
  end

  context 'with a persisted record' do
    let(:record) { model.create!(roles: [:author]) }

    it 'keeps the other flags' do
      record.admin!

      expect(raw_value(record)).to eq(0b101)
    end

    it 'is idempotent' do
      record.admin!
      record.admin!

      expect(raw_value(record)).to eq(0b101)
    end

    it 'keeps unmapped bits stored in the database' do
      stored = plant_raw_value(record, 0b1_0000_0100)
      stored.admin!

      expect(raw_value(stored)).to eq(0b1_0000_0101)
    end

    it 'leaves the record without unsaved changes' do
      record.admin!

      expect(record.changed?).to be(false)
    end

    it 'returns true' do
      expect(record.admin!).to be(true)
    end
  end

  context 'with an invalid record' do
    let(:validated) do
      build_model do
        bitwise :roles, { admin: 0 }
        validates :name, presence: true
      end
    end

    it 'raises ActiveRecord::RecordInvalid' do
      expect { validated.new.admin! }
        .to raise_error(ActiveRecord::RecordInvalid, "Validation failed: Name can't be blank")
    end

    it 'does not persist anything' do
      capture_error { validated.new.admin! }

      expect(validated.count).to eq(0)
    end
  end

  context 'with a prefixed flag' do
    it 'is generated with the prefix' do
      record = model.create!
      record.legacy_admin!

      expect(raw_value(record, :legacy_roles)).to eq(1)
    end
  end
end
