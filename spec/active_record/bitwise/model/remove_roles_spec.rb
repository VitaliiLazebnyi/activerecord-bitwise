# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '.remove_roles!' do
  include_context 'with a user model'

  let!(:both) { model.create!(roles: %i[admin author]) }
  let!(:author) { model.create!(roles: [:author]) }

  context 'when choosing the records' do
    it 'updates a single record' do
      model.remove_roles!(:author, records: both)

      expect(raw_value(both)).to eq(1)
    end

    it 'updates a single id' do
      model.remove_roles!(:author, records: both.id)

      expect(raw_value(both)).to eq(1)
    end

    it 'updates an array of records' do
      model.remove_roles!(:author, records: [both, author])

      expect([raw_value(both), raw_value(author)]).to eq([1, 0])
    end

    it 'updates an array of ids' do
      model.remove_roles!(:author, records: [both.id, author.id])

      expect([raw_value(both), raw_value(author)]).to eq([1, 0])
    end

    it 'leaves other records untouched' do
      model.remove_roles!(:author, records: both)

      expect(raw_value(author)).to eq(0b100)
    end

    it 'does nothing for an empty list' do
      model.remove_roles!(:author, records: [])

      expect(raw_value(both)).to eq(0b101)
    end

    it 'returns nil for an empty list' do
      expect(model.remove_roles!(:author, records: [])).to be_nil
    end

    it 'requires the records: keyword' do
      expect { model.remove_roles!(:admin) }.to raise_error(ArgumentError, 'missing keyword: :records')
    end
  end

  context 'when choosing the values' do
    it 'removes several values' do
      model.remove_roles!(:admin, :author, records: both)

      expect(raw_value(both)).to eq(0)
    end

    it 'accepts a nested array of Strings' do
      model.remove_roles!(%w[admin author], records: both)

      expect(raw_value(both)).to eq(0)
    end

    it 'applies the known values and ignores the unknown ones' do
      model.remove_roles!(:bogus, :admin, records: both)

      expect(raw_value(both)).to eq(0b100)
    end

    it 'does nothing when every value is unknown' do
      model.remove_roles!(:bogus, records: both)

      expect(raw_value(both)).to eq(0b101)
    end

    it 'returns nil when every value is unknown' do
      expect(model.remove_roles!(:bogus, records: both)).to be_nil
    end

    it 'does nothing without values' do
      model.remove_roles!(records: both)

      expect(raw_value(both)).to eq(0b101)
    end

    it 'does not create Symbols from untrusted values' do
      payload = unique_unmapped_name
      model.remove_roles!(payload, records: both)

      expect(symbol_exists?(payload)).to be(false)
    end
  end

  context 'when the flag is not set' do
    it 'keeps the bitmask unchanged instead of subtracting the mask' do
      model.remove_roles!(:admin, records: author)

      expect(raw_value(author)).to eq(0b100)
    end
  end

  context 'with a NULL column' do
    it 'leaves zero' do
      plant_raw_value(author, nil)
      model.remove_roles!(:author, records: author)

      expect(raw_value(author)).to eq(0)
    end
  end

  context 'with unmapped bits stored in the database' do
    it 'keeps them' do
      stored = plant_raw_value(both, 0b1_0000_0101)
      model.remove_roles!(:admin, records: stored)

      expect(raw_value(stored)).to eq(0b1_0000_0100)
    end
  end

  context 'with the generated SQL' do
    it 'subtracts the masked bits from the COALESCEd column' do
      column = model.connection.quote_column_name('roles')
      expected = "#{column} = COALESCE(#{column}, 0) - (COALESCE(#{column}, 0) & 4)"
      statements = normalized_sql(capture_sql { model.remove_roles!(:author, records: both.id) })

      expect(statements).to include(a_string_including(expected))
    end
  end
end
