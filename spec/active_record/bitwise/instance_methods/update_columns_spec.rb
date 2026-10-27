# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::InstanceMethods, '#update_columns' do
  include_context 'with a user model'

  # admin + the unmapped bits 8 and 9
  let(:record) { plant_raw_value(model.create!, 0b11_0000_0001) }

  # Decision table: value written -> raw column afterwards.
  [
    [[:author], 0b11_0000_0100],
    [%w[author], 0b11_0000_0100],
    [%i[admin author], 0b11_0000_0101],
    [[], 0b11_0000_0000],
    [3, 3],
    [0, 0],
    [nil, nil]
  ].each do |value, expected_raw|
    it "stores #{expected_raw.inspect} for roles: #{value.inspect}" do
      record.update_columns(roles: value)

      expect(raw_value(record)).to eq(expected_raw)
    end
  end

  context 'with the singular update_column' do
    it 'keeps the unmapped bits' do
      record.update_column(:roles, [:subscriber])

      expect(raw_value(record)).to eq(0b11_0000_1000)
    end
  end

  context 'with a String key' do
    it 'keeps the unmapped bits' do
      record.update_columns({ roles: [:author] }.transform_keys(&:to_s))

      expect(raw_value(record)).to eq(0b11_0000_0100)
    end
  end

  context 'with the in-memory attribute' do
    it 'shows the new flags' do
      record.update_columns(roles: [:author])

      expect(record.roles).to eq([:author])
    end

    it 'shows the flags of an Integer overwrite' do
      record.update_columns(roles: 3)

      expect(record.roles).to eq(%i[admin editor])
    end

    it 'leaves no unsaved change behind' do
      record.update_columns(roles: [:author])

      expect(record.roles_changed?).to be(false)
    end
  end

  context 'with a stale record' do
    it 'merges later saves against the value that update_column wrote' do
      stale = model.create!(roles: [:admin])
      stale.update_column(:roles, 2)
      stale.author = true
      stale.save!

      expect(raw_value(stale)).to eq(0b110)
    end

    it 'keeps unmapped bits written by update_columns for later saves' do
      record.update_columns(roles: [:author])
      record.update!(roles: %i[author subscriber])

      expect(raw_value(record)).to eq(0b11_0000_1100)
    end
  end

  context 'with several columns' do
    it 'writes every bitwise column' do
      record.update_columns(roles: [:author], permissions: [:manage])

      expect([raw_value(record), raw_value(record, :permissions)]).to eq([0b11_0000_0100, 0b10])
    end

    it 'passes non-bitwise columns through' do
      record.update_columns(name: 'Ada', roles: [:author])

      expect(record.reload.name).to eq('Ada')
    end

    it 'writes only the ordinary column when given only that' do
      record.update_columns(name: 'Ada')

      expect(raw_value(record)).to eq(0b11_0000_0001)
    end
  end

  context 'with a column whose type was replaced after declaring it bitwise' do
    it 'writes the value untouched' do
      model.attribute :roles, :integer
      record.update_columns(roles: 5)

      expect(raw_value(record)).to eq(5)
    end
  end

  context 'with an unknown attribute' do
    it 'raises MissingAttributeError like plain ActiveRecord' do
      expect { record.update_columns(missing: 1) }
        .to raise_error(ActiveModel::MissingAttributeError, /unknown attribute .missing./)
    end
  end
end
