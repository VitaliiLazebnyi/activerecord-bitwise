# typed: false
# frozen_string_literal: true

# These examples need rows that are committed and visible to other connections, so they rely on
# the global cleanup in spec_helper (rows are deleted before every example) instead of a
# rolled-back transaction.
RSpec.describe 'Concurrent updates' do
  include_context 'with a user model'

  let(:user_id) { model.create!(roles: initial_roles).id }
  let(:initial_roles) { [] }

  describe 'a read-modify-write cycle with save' do
    let(:initial_roles) { [] }

    it 'loses an update when two stale copies are saved one after the other' do
      first = model.find(user_id)
      second = model.find(user_id)
      first.update!(roles: first.roles + [:admin])
      second.update!(roles: second.roles + [:editor])

      expect(model.find(user_id).roles).to eq([:editor])
    end
  end

  describe 'instance atomic methods' do
    it 'merges simultaneous additions of different flags' do
      tasks = %i[admin editor author].map { |flag| -> { model.find(user_id).add_role!(flag) } }
      run_concurrently(*tasks)

      expect(raw_value(model.find(user_id))).to eq(0b0111)
    end

    it 'merges a simultaneous addition and removal of different flags' do
      stored = model.create!(roles: %i[admin subscriber])
      run_concurrently(-> { model.find(stored.id).add_role!(:author) },
                       -> { model.find(stored.id).remove_role!(:subscriber) })

      expect(raw_value(stored)).to eq(0b0101)
    end

    it 'is idempotent when the same flag is added simultaneously' do
      run_concurrently(*Array.new(4) { -> { model.find(user_id).add_role!(:admin) } })

      expect(raw_value(model.find(user_id))).to eq(1)
    end

    it 'keeps unmapped bits during simultaneous additions' do
      plant_raw_value(model.find(user_id), 0b1_0000_0000)
      run_concurrently(-> { model.find(user_id).add_role!(:admin) }, -> { model.find(user_id).add_role!(:author) })

      expect(raw_value(model.find(user_id))).to eq(0b1_0000_0101)
    end
  end

  describe 'class-level atomic methods' do
    it 'merges simultaneous additions of different flags' do
      tasks = %i[admin editor author subscriber].map { |flag| -> { model.add_roles!(flag, records: user_id) } }
      run_concurrently(*tasks)

      expect(raw_value(model.find(user_id))).to eq(0b1111)
    end

    it 'merges simultaneous removals of different flags' do
      stored = model.create!(roles: %i[admin editor author subscriber])
      tasks = %i[admin author].map { |flag| -> { model.remove_roles!(flag, records: stored.id) } }
      run_concurrently(*tasks)

      expect(raw_value(stored)).to eq(0b1010)
    end
  end
end
