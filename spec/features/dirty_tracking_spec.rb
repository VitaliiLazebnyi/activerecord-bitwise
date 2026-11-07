# typed: false
# frozen_string_literal: true

RSpec.describe 'Dirty tracking' do
  include_context 'with a user model'

  # State transition table: flags stored -> value assigned -> is the column considered changed?
  describe 'assigning a value to a persisted record' do
    [
      [[:admin], [:admin], false],
      [[:admin], ['admin'], false],
      [[:admin], 1, false],
      [[:admin], %i[admin author], true],
      [[:admin], [], true],
      [[:admin], nil, true],
      [[:admin], 0, true],
      [[], [], false],
      [[], 0, false],
      [%i[admin author], %i[author admin], true],
      [[:admin], 0b1_0000_0001, true]
    ].each do |stored, assigned, changed|
      it "reports changed? #{changed} when #{stored.inspect} becomes #{assigned.inspect}" do
        record = model.create!(roles: stored)
        record.roles = assigned

        expect(record.roles_changed?).to be(changed)
      end
    end
  end

  describe 'assigning the original value back' do
    it 'ends up unchanged' do
      record = model.create!(roles: [:admin])
      record.roles = [:author]
      record.roles = [:admin]

      expect(record.roles_changed?).to be(false)
    end
  end

  describe 'a changed record' do
    let(:record) do
      stored = model.create!(roles: [:admin])
      stored.roles = %i[admin author]
      stored
    end

    it 'exposes the previous flags' do
      expect(record.roles_was).to eq([:admin])
    end

    it 'exposes the change as before and after' do
      expect(record.roles_change).to eq([[:admin], %i[admin author]])
    end

    it 'lists the column among the changes' do
      expect(record.changes['roles']).to eq([[:admin], %i[admin author]])
    end

    it 'lists the column among the changed attributes' do
      expect(record.changed).to eq(['roles'])
    end

    it 'restores the previous flags' do
      record.restore_roles!

      expect(record.roles).to eq([:admin])
    end

    it 'reports an unsaved change to be saved' do
      expect(record.will_save_change_to_roles?).to be(true)
    end
  end

  describe 'a new record' do
    it 'starts the column from the empty flags' do
      expect(model.new.roles).to eq([])
    end

    it 'reports the column as changed after assigning flags' do
      record = model.new
      record.roles = [:admin]

      expect(record.roles_changed?).to be(true)
    end
  end

  describe 'saving' do
    let(:record) do
      stored = model.create!(roles: [:admin])
      stored.update!(roles: [:author])
      stored
    end

    it 'clears the pending change' do
      expect(record.roles_changed?).to be(false)
    end

    it 'remembers the saved change' do
      expect(record.saved_change_to_roles).to eq([[:admin], [:author]])
    end

    it 'remembers the previous flags' do
      expect(record.roles_previously_was).to eq([:admin])
    end
  end

  describe 'a change that only differs in unmapped bits' do
    it 'is persisted by the next save' do
      record = model.create!(roles: [:admin])
      record.roles = 0b1_0000_0001
      record.save!

      expect(raw_value(record)).to eq(0b1_0000_0001)
    end
  end

  describe 'a reordered assignment' do
    it 'is reported as changed, because arrays compare in order' do
      record = model.create!(roles: %i[admin author])
      record.roles = %i[author admin]

      expect(record.roles_changed?).to be(true)
    end

    it 'still stores the same bitmask' do
      record = model.create!(roles: %i[admin author])
      record.update!(roles: %i[author admin])

      expect(raw_value(record)).to eq(0b101)
    end
  end

  describe 'reloading' do
    it 'discards pending changes' do
      record = model.create!(roles: [:admin])
      record.roles = [:author]
      record.reload

      expect(record.roles_changed?).to be(false)
    end
  end
end
