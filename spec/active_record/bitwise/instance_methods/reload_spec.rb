# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::InstanceMethods, '#reload' do
  include_context 'with a user model'

  let!(:record) { model.create!(roles: [:admin]) }

  it 'returns the record itself' do
    expect(record.reload).to equal(record)
  end

  it 'accepts the options of ActiveRecord reload' do
    expect(record.reload(lock: true)).to equal(record)
  end

  it 'shows the flags stored in the database' do
    plant_raw_value(record, 0b10)

    expect(record.roles).to eq([:editor])
  end

  it 'discards unsaved flag changes' do
    record.roles = [:subscriber]
    record.reload

    expect(record.roles).to eq([:admin])
  end

  context 'when unmapped bits changed in the database' do
    it 'forgets the unmapped bits that disappeared' do
      plant_raw_value(record, 0b1_0000_0001)
      ActiveRecord::Base.connection.execute('UPDATE users SET roles = 4')
      record.reload
      record.update!(roles: [:admin])

      expect(raw_value(record)).to eq(1)
    end

    it 'picks up unmapped bits that appeared' do
      ActiveRecord::Base.connection.execute('UPDATE users SET roles = 1025')
      record.reload
      record.update!(roles: [:author])

      expect(raw_value(record)).to eq(0b100_0000_0100)
    end
  end

  context 'when the record was saved earlier' do
    it 'does not re-save a stale unmapped bit' do
      stored = plant_raw_value(record, 0b1_0000_0001)
      stored.update!(roles: [:author])
      ActiveRecord::Base.connection.execute('UPDATE users SET roles = 4')
      stored.reload.update!(roles: [:admin])

      expect(raw_value(stored)).to eq(1)
    end
  end

  it 'asks the database to lock the row when told to' do
    relation = model.all
    allow(model).to receive(:all).and_return(relation)
    allow(relation).to receive_messages(preload: relation, lock: relation.lock(true))
    record.reload(lock: true)

    expect(relation).to have_received(:lock).with(true)
  end

  it 'picks up unmapped bits that were changed elsewhere' do
    record.roles
    plant_raw_value(model.find(record.id), 0b10_0000_0001)
    record.reload
    record.update!(roles: %i[admin author])

    expect(raw_value(record)).to eq(0b10_0000_0101)
  end
end
