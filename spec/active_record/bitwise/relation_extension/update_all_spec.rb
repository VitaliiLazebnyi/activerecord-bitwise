# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::RelationExtension, '#update_all' do
  include_context 'with a user model'

  # admin + author + the unmapped bit 4 (value 16)
  let!(:ghosted) { plant_raw_value(model.create!, 0b1_0000_0101) }
  let!(:plain) { model.create!(roles: [:editor]) }

  # Decision table: value assigned -> raw column afterwards for the ghosted row.
  [
    [[:subscriber], 0b1_0000_1000],
    [%w[author], 0b1_0000_0100],
    [%i[admin author], 0b1_0000_0101],
    [%i[author admin], 0b1_0000_0101],
    [[], 0b1_0000_0000],
    [:editor, 0b1_0000_0010],
    ['editor', 0b1_0000_0010],
    [7, 7],
    [0, 0],
    [nil, nil]
  ].each do |value, expected_raw|
    it "stores #{expected_raw.inspect} for roles: #{value.inspect}" do
      model.where(id: ghosted.id).update_all(roles: value)

      expect(raw_value(ghosted)).to eq(expected_raw)
    end
  end

  context 'with SQL expressions' do
    it 'passes an Arel SQL literal through' do
      model.where(id: ghosted.id).update_all(roles: Arel.sql('0 + 3'))

      expect(raw_value(ghosted)).to eq(3)
    end

    it 'passes an Arel node through' do
      model.where(id: ghosted.id).update_all(roles: model.arel_table[:roles] + 2)

      expect(raw_value(ghosted)).to eq(0b1_0000_0111)
    end

    it 'passes a SQL string through' do
      model.where(id: ghosted.id).update_all('roles = 3')

      expect(raw_value(ghosted)).to eq(3)
    end
  end

  context 'with several rows' do
    before { model.update_all(roles: [:author]) }

    it 'keeps the unmapped bits of each row individually' do
      expect([raw_value(ghosted), raw_value(plain)]).to eq([0b1_0000_0100, 0b0100])
    end
  end

  context 'with a row whose column is NULL' do
    it 'sets the flags' do
      nulled = plant_raw_value(plain, nil)
      model.where(id: nulled.id).update_all(roles: [:admin])

      expect(raw_value(nulled)).to eq(1)
    end
  end

  context 'with flags read from a record that has unmapped bits' do
    it 'does not copy those unmapped bits to the updated rows' do
      model.where(id: plain.id).update_all(roles: ghosted.roles)

      expect(raw_value(plain)).to eq(0b0101)
    end
  end

  context 'with a String key' do
    it 'serializes the flags' do
      model.where(id: plain.id).update_all({ roles: ['author'] }.transform_keys(&:to_s))

      expect(raw_value(plain)).to eq(0b0100)
    end

    it 'keeps the unmapped bits like a Symbol key does' do
      model.where(id: ghosted.id).update_all({ roles: ['author'] }.transform_keys(&:to_s))

      expect(raw_value(ghosted)).to eq(0b1_0000_0100)
    end
  end

  context 'with an unknown flag' do
    it 'raises UnknownValueError with the full explanation' do
      expect { model.update_all(roles: %i[admin bogus]) }.to raise_error(
        ActiveRecord::Bitwise::UnknownValueError,
        'Unknown bitwise value(s) ["bogus"] for column roles; refusing to zero unrecognized flags via update_all'
      )
    end

    it 'changes no row' do
      capture_error { model.update_all(roles: [:bogus]) }

      expect([raw_value(ghosted), raw_value(plain)]).to eq([0b1_0000_0101, 0b0010])
    end
  end

  context 'with a bitwise and an ordinary column' do
    it 'updates both' do
      model.where(id: plain.id).update_all(roles: [:admin], permissions: 2)

      expect([raw_value(plain), raw_value(plain, :permissions)]).to eq([1, 2])
    end

    it 'updates only the ordinary column when given only that' do
      model.where(id: plain.id).update_all(permissions: 3)

      expect([raw_value(plain), raw_value(plain, :permissions)]).to eq([0b10, 3])
    end
  end

  context 'with the return value' do
    it 'returns the number of affected rows' do
      expect(model.update_all(roles: [:admin])).to eq(2)
    end
  end

  context 'with a model without bitwise columns' do
    it 'behaves like plain ActiveRecord' do
      build_model.where(id: plain.id).update_all(name: 'Ada')

      expect(plain.reload.name).to eq('Ada')
    end
  end

  context 'with a column whose type was replaced after declaring it bitwise' do
    it 'leaves the value to the new type' do
      model.attribute :roles, :integer
      model.where(id: plain.id).update_all(roles: '6')

      expect(raw_value(plain)).to eq(6)
    end
  end

  describe 'generated SQL' do
    it 'keeps the unmapped bits and ORs in the mask' do
      column = model.connection.quote_column_name('roles')
      statements = capture_sql { model.where(id: plain.id).update_all(roles: [:admin]) }

      expect(statements).to include(a_string_including("(COALESCE(#{column}, 0) & -16) | 1"))
    end
  end

  context 'with an Integer for one column and flags for the next' do
    it 'still rewrites the flags' do
      model.where(id: plain.id).update_all(roles: 1, permissions: [:manage])

      expect([raw_value(plain), raw_value(plain, :permissions)]).to eq([1, 2])
    end
  end

  context 'with a hash that is reused by the caller' do
    it 'does not modify the hash' do
      updates = { roles: [:admin] }
      model.where(id: plain.id).update_all(updates)

      expect(updates).to eq(roles: [:admin])
    end
  end
end
