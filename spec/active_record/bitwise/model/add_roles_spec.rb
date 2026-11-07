# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '.add_roles!' do
  include_context 'with a user model'

  let!(:admin) { model.create!(roles: [:admin]) }
  let!(:author) { model.create!(roles: [:author]) }

  context 'when a flag is named more than once' do
    it 'sets it once' do
      model.add_roles!(:subscriber, :subscriber, records: admin)

      expect(raw_value(admin)).to eq(0b1001)
    end
  end

  context 'when choosing the records' do
    it 'updates a single record' do
      model.add_roles!(:subscriber, records: admin)

      expect(raw_value(admin)).to eq(0b1001)
    end

    it 'updates a single id' do
      model.add_roles!(:subscriber, records: admin.id)

      expect(raw_value(admin)).to eq(0b1001)
    end

    it 'updates an array of records' do
      model.add_roles!(:editor, records: [admin, author])

      expect([raw_value(admin), raw_value(author)]).to eq([0b0011, 0b0110])
    end

    it 'updates an array of ids' do
      model.add_roles!(:editor, records: [admin.id, author.id])

      expect([raw_value(admin), raw_value(author)]).to eq([0b0011, 0b0110])
    end

    it 'leaves other records untouched' do
      model.add_roles!(:editor, records: admin)

      expect(raw_value(author)).to eq(0b0100)
    end

    it 'does nothing for an empty list' do
      model.add_roles!(:editor, records: [])

      expect([raw_value(admin), raw_value(author)]).to eq([1, 4])
    end

    it 'returns nil for an empty list' do
      expect(model.add_roles!(:editor, records: [])).to be_nil
    end

    it 'does nothing for nil' do
      model.add_roles!(:editor, records: nil)

      expect(raw_value(admin)).to eq(1)
    end

    it 'requires the records: keyword' do
      expect { model.add_roles!(:admin) }.to raise_error(ArgumentError, 'missing keyword: :records')
    end
  end

  context 'when choosing the values' do
    it 'accepts several values' do
      model.add_roles!(:editor, :subscriber, records: admin)

      expect(raw_value(admin)).to eq(0b1011)
    end

    it 'accepts a nested array' do
      model.add_roles!(%i[editor subscriber], records: admin)

      expect(raw_value(admin)).to eq(0b1011)
    end

    it 'accepts Strings' do
      model.add_roles!('editor', records: admin)

      expect(raw_value(admin)).to eq(0b0011)
    end

    it 'applies the known values and ignores the unknown ones' do
      model.add_roles!(:bogus, :editor, records: admin)

      expect(raw_value(admin)).to eq(0b0011)
    end

    it 'does nothing when every value is unknown' do
      model.add_roles!(:bogus, records: admin)

      expect(raw_value(admin)).to eq(1)
    end

    it 'returns nil when every value is unknown' do
      expect(model.add_roles!(:bogus, records: admin)).to be_nil
    end

    it 'does nothing without values' do
      model.add_roles!(records: admin)

      expect(raw_value(admin)).to eq(1)
    end

    it 'ignores Integers instead of treating them as bitmasks' do
      model.add_roles!(2, records: admin)

      expect(raw_value(admin)).to eq(1)
    end

    it 'does not create Symbols from untrusted values' do
      payload = unique_unmapped_name
      model.add_roles!(payload, records: admin)

      expect(symbol_exists?(payload)).to be(false)
    end
  end

  context 'when the flag is already set' do
    it 'keeps the bitmask unchanged' do
      model.add_roles!(:admin, records: admin)

      expect(raw_value(admin)).to eq(1)
    end
  end

  context 'with a NULL column' do
    it 'treats NULL as no flags' do
      plant_raw_value(admin, nil)
      model.add_roles!(:author, records: admin)

      expect(raw_value(admin)).to eq(0b100)
    end
  end

  context 'with unmapped bits stored in the database' do
    it 'keeps them' do
      stored = plant_raw_value(admin, 0b1_0000_0001)
      model.add_roles!(:author, records: stored)

      expect(raw_value(stored)).to eq(0b1_0000_0101)
    end
  end

  context 'with the highest bit position' do
    it 'sets bit 62 on a bigint column' do
      wide = build_model('capacity_records') { bitwise :big, { low: 0, top: 62 } }
      record = wide.create!
      wide.add_big!(:top, records: record)

      expect(raw_value(record, :big)).to eq(1 << 62)
    end
  end

  context 'with the generated SQL' do
    it 'ORs the mask into the COALESCEd column in one UPDATE' do
      column = model.connection.quote_column_name('roles')
      statements = normalized_sql(capture_sql { model.add_roles!(:admin, records: admin.id) })

      expect(statements).to include(a_string_including("#{column} = COALESCE(#{column}, 0) | 1"))
    end

    it 'issues a single statement' do
      expect(capture_sql { model.add_roles!(:admin, records: admin.id) }.size).to eq(1)
    end
  end

  describe 'the class method behind it' do
    it 'is private' do
      expect([model.respond_to?(:_bitwise_add_roles), model.respond_to?(:_bitwise_add_roles, true)])
        .to eq([false, true])
    end
  end
end
