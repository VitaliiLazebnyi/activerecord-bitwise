# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#admin?' do
  include_context 'with a user model'

  let(:record) { model.new }

  context 'when the flag is set' do
    it 'returns true' do
      record.roles = %i[author admin]

      expect(record.admin?).to be(true)
    end
  end

  context 'when only other flags are set' do
    it 'returns false' do
      record.roles = [:author]

      expect(record.admin?).to be(false)
    end
  end

  context 'when no flag is set' do
    it 'returns false' do
      expect(record.admin?).to be(false)
    end
  end

  context 'when the same key exists on another bitwise column' do
    it 'only looks at its own column' do
      record.legacy_roles = [:admin]

      expect(record.admin?).to be(false)
    end

    it 'answers the prefixed predicate for the other column' do
      record.legacy_roles = [:admin]

      expect(record.legacy_admin?).to be(true)
    end
  end

  context 'with a persisted record that has the bit set' do
    it 'returns true' do
      expect(plant_raw_value(model.create!, 0b1_0001).admin?).to be(true)
    end
  end
end
