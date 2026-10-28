# typed: false
# frozen_string_literal: true

# "Ghost bits" are bits of the column that the mapping does not name (legacy flags, flags of a
# newer release during a rolling deploy). Every write path must keep them, except the ones that
# are documented to replace the whole bitmask.
RSpec.describe 'Ghost (unmapped) bits' do
  include_context 'with a user model'

  # admin (bit 0) plus the unmapped bits 8 and 9
  let(:stored) { 0b11_0000_0001 }
  let(:record) { plant_raw_value(model.create!, stored) }

  describe 'reading' do
    it 'hides unmapped bits from the flags' do
      expect(record.roles).to eq([:admin])
    end

    it 'leaves unmapped bits in the database when only reading' do
      record.roles

      expect(raw_value(record)).to eq(stored)
    end
  end

  # State transition table: operation applied to the record -> bitmask stored afterwards.
  describe 'writing with a flag array keeps unmapped bits' do
    [
      ['assigning with the setter', ->(r) { r.update!(roles: %i[admin author]) }, 0b11_0000_0101],
      ['assigning an empty array', ->(r) { r.update!(roles: []) }, 0b11_0000_0000],
      ['assigning with []=', ->(r) { r.tap { |x| x[:roles] = [:subscriber] }.save! }, 0b11_0000_1000],
      ['assigning with write_attribute', ->(r) { r.tap { |x| x.write_attribute(:roles, [:author]) }.save! },
       0b11_0000_0100],
      ['enabling a flag', ->(r) { r.tap { |x| x.author = true }.save! }, 0b11_0000_0101],
      ['disabling a flag', ->(r) { r.tap { |x| x.admin = false }.save! }, 0b11_0000_0000],
      ['the flag bang method', lambda(&:author!), 0b11_0000_0101],
      ['update_columns', ->(r) { r.update_columns(roles: [:author]) }, 0b11_0000_0100],
      ['update_column', ->(r) { r.update_column(:roles, [:subscriber]) }, 0b11_0000_1000],
      ['relation update_all', ->(r) { r.class.where(id: r.id).update_all(roles: [:author]) }, 0b11_0000_0100],
      ['class-level add_roles!', ->(r) { r.class.add_roles!(:author, records: r) }, 0b11_0000_0101],
      ['class-level remove_roles!', ->(r) { r.class.remove_roles!(:admin, records: r) }, 0b11_0000_0000],
      ['instance add_role!', ->(r) { r.add_role!(:author) }, 0b11_0000_0101],
      ['instance remove_role!', ->(r) { r.remove_role!(:admin) }, 0b11_0000_0000]
    ].each do |operation, action, expected_raw|
      it "stores #{expected_raw.to_s(2)} after #{operation}" do
        action.call(record)

        expect(raw_value(record)).to eq(expected_raw)
      end
    end
  end

  describe 'writing something other than flags replaces the whole bitmask' do
    [
      ['assigning an Integer', ->(r) { r.update!(roles: 2) }, 2],
      ['assigning 0', ->(r) { r.update!(roles: 0) }, 0],
      ['assigning nil', ->(r) { r.update!(roles: nil) }, nil],
      ['update_columns with an Integer', ->(r) { r.update_columns(roles: 3) }, 3],
      ['update_columns with nil', ->(r) { r.update_columns(roles: nil) }, nil],
      ['relation update_all with an Integer', ->(r) { r.class.update_all(roles: 7) }, 7],
      ['relation update_all with nil', ->(r) { r.class.update_all(roles: nil) }, nil]
    ].each do |operation, action, expected_raw|
      it "stores #{expected_raw.inspect} after #{operation}" do
        action.call(record)

        expect(raw_value(record)).to eq(expected_raw)
      end
    end
  end

  describe 'duplicating the record' do
    it 'does not copy unmapped bits to the duplicate' do
      duplicate = record.dup
      duplicate.save!

      expect(raw_value(duplicate)).to eq(0b1)
    end
  end

  describe 'saving a record whose flags were not touched' do
    it 'keeps unmapped bits' do
      record.update!(name: 'Ada')

      expect(raw_value(record)).to eq(stored)
    end
  end

  describe 'when the stored value changes behind the record' do
    it 'uses the newly loaded unmapped bits after reload' do
      plant_raw_value(model.find(record.id), 0b1_0000_0100)
      record.reload.update!(roles: [:admin])

      expect(raw_value(record)).to eq(0b1_0000_0001)
    end
  end

  describe 'when a later release maps a previously unmapped bit' do
    it 'shows the old data as the new flag' do
      later_release = build_model { bitwise :roles, { admin: 0, legacy_flag: 8 } }

      expect(later_release.find(record.id).roles).to eq(%i[admin legacy_flag])
    end
  end
end
