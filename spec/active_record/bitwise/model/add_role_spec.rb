# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#add_role!' do
  include_context 'with a user model'

  let!(:record) { model.create!(roles: [:author]) }

  context 'with a persisted record' do
    it 'adds the flag in the database' do
      record.add_role!(:admin)

      expect(raw_value(record)).to eq(0b101)
    end

    it 'updates the in-memory flags' do
      record.add_role!(:admin)

      expect(record.roles).to eq(%i[admin author])
    end

    it 'adds several flags at once' do
      record.add_role!(:admin, :subscriber)

      expect(record.roles).to eq(%i[admin author subscriber])
    end

    it 'accepts Strings' do
      record.add_role!('admin')

      expect(record.roles).to eq(%i[admin author])
    end

    it 'ignores unknown values' do
      record.add_role!(:bogus, :admin)

      expect(raw_value(record)).to eq(0b101)
    end

    it 'does not leave the record with unsaved changes' do
      record.add_role!(:admin)

      expect(record.changed?).to be(false)
    end

    it 'is also available under the plural name' do
      record.add_roles!(:admin)

      expect(record.roles).to eq(%i[admin author])
    end

    it 'leaves other bitwise columns alone' do
      record.add_role!(:admin)

      expect(raw_value(record, :permissions)).to eq(1)
    end

    it 'leaves unsaved changes to other attributes unsaved' do
      record.name = 'Ada'
      record.add_role!(:admin)

      expect(record.name_changed?).to be(true)
    end
  end

  context 'when the database changed since the record was loaded' do
    it 'builds on the current database value' do
      plant_raw_value(record, 0b1010)
      stale = model.find(record.id)
      plant_raw_value(record, 0b1000)
      stale.add_role!(:author)

      expect(stale.roles).to eq(%i[author subscriber])
    end

    it 'replaces unsaved flag changes with the database state' do
      record.roles = [:editor]
      record.add_role!(:admin)

      expect(record.roles).to eq(%i[admin author])
    end
  end

  context 'with unmapped bits stored in the database' do
    it 'keeps them in the database' do
      plant_raw_value(record, 0b1_0000_0100)
      record.add_role!(:admin)

      expect(raw_value(record)).to eq(0b1_0000_0101)
    end

    it 'keeps them through a later ordinary save' do
      plant_raw_value(record, 0b1_0000_0001)
      record.add_role!(:author)
      record.update!(roles: record.roles + [:subscriber])

      expect(raw_value(record)).to eq(0b1_0000_1101)
    end
  end

  context 'with a new record' do
    it 'raises ActiveRecordError telling to save first' do
      expect { model.new.add_role!(:admin) }.to raise_error(
        ActiveRecord::ActiveRecordError, 'cannot atomically add roles on a new record; save the record first'
      )
    end
  end

  context 'when the record lacks dirty tracking support' do
    it 'still applies the change' do
      allow(record).to receive(:respond_to?).and_call_original
      allow(record).to receive(:respond_to?).with(:clear_attribute_changes).and_return(false)
      record.add_role!(:admin)

      expect(record.roles).to eq(%i[admin author])
    end
  end

  context 'when reading and writing the row' do
    it 'runs every statement inside one transaction' do
      statements = capture_sql_with_transaction_state(model.connection) { record.add_role!(:admin) }

      expect(statements.map(&:last)).to all(be(true))
    end

    it 'locks the row while reading it back' do
      locks = track_row_locks(model)
      record.add_role!(:admin)

      expect(locks).to eq([[true]])
    end

    it 'issues an UPDATE followed by a SELECT' do
      statements = capture_sql { record.add_role!(:admin) }

      expect(statements.map { |sql| sql.split.first }).to eq(%w[UPDATE SELECT])
    end
  end

  context 'with a column whose name is already singular' do
    let(:singular) { build_model('singular_models') { bitwise :status, { active: 0, archived: 1 } } }

    it 'adds the flag' do
      stored = singular.create!
      stored.add_status!(:archived)

      expect(stored.reload.status).to eq([:archived])
    end

    it 'defines no plural alias' do
      expect(singular.new).not_to respond_to(:add_statuses!)
    end
  end

  context 'with an uncountable column name' do
    it 'adds the flag' do
      fish = build_model('singular_models') { bitwise :fish, { salmon: 0, trout: 1 } }.create!
      fish.add_fish!(:trout)

      expect(fish.reload.fish).to eq([:trout])
    end
  end

  context 'when the unmapped bits changed in the database since the record was loaded' do
    it 'saves later changes on top of the current unmapped bits' do
      plant_raw_value(model.find(record.id), 0b10_0000_0100)
      record.add_role!(:admin)
      record.update!(roles: record.roles + [:subscriber])

      expect(raw_value(record)).to eq(0b10_0000_1101)
    end
  end
end
