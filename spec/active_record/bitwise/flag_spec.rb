# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Flag do
  subject(:flag) { described_class.new(:roles, :admin) }

  include_context 'with a user model'

  let(:record) { model.new(roles: [:editor]) }

  describe '#writer' do
    it('is the setter of the column') { expect(flag.writer).to eq('roles=') }
  end

  describe '#in?' do
    it('is true for a listed flag') { expect(flag.in?(%i[editor admin])).to be(true) }
    it('is false for an unlisted flag') { expect(flag.in?([:editor])).to be(false) }
  end

  describe '#added_to' do
    it 'appends the flag to a copy' do
      flags = [:editor]

      expect(flag.added_to(flags)).to eq(%i[editor admin])
    end

    it 'leaves the given flags alone' do
      flags = [:editor]
      flag.added_to(flags)

      expect(flags).to eq([:editor])
    end

    it 'does not duplicate a flag that is already present' do
      expect(flag.added_to(%i[admin editor])).to eq(%i[admin editor])
    end

    it 'returns a copy even when the flag is present' do
      flags = [:admin]

      expect(flag.added_to(flags)).not_to equal(flags)
    end
  end

  describe '#removed_from' do
    it 'removes every occurrence from a copy' do
      flags = %i[admin editor admin]

      expect(flag.removed_from(flags)).to eq([:editor])
    end

    it 'leaves the given flags alone' do
      flags = %i[admin editor]
      flag.removed_from(flags)

      expect(flags).to eq(%i[admin editor])
    end
  end

  describe '#set?' do
    it('is false when the record lacks the flag') { expect(flag.set?(record)).to be(false) }

    it 'is true when the record has the flag' do
      record.roles = [:admin]

      expect(flag.set?(record)).to be(true)
    end
  end

  describe '#set' do
    it 'adds the flag to the record' do
      flag.set(record)

      expect(record.roles).to eq(%i[editor admin])
    end
  end

  describe '#clear' do
    it 'removes the flag from the record' do
      record.roles = %i[admin editor]
      flag.clear(record)

      expect(record.roles).to eq([:editor])
    end
  end
end
