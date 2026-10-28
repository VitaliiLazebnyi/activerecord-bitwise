# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise, '.serialize_conditions' do
  include_context 'with a user model'

  let(:serialize) { ->(conditions) { described_class.serialize_conditions(model, conditions) } }

  context 'when the attribute types do not know a bitwise column' do
    it 'leaves the conditions as they are' do
      allow(model).to receive(:attribute_types).and_return({})

      expect(serialize.call(roles: [:admin])).to eq(roles: [:admin])
    end
  end

  context 'with flag values for a bitwise column' do
    it 'turns a Symbol array into its exact bitmask' do
      expect(serialize.call(roles: %i[admin author])).to eq(roles: 0b101)
    end

    it 'turns a String array into its exact bitmask' do
      expect(serialize.call(roles: %w[editor subscriber])).to eq(roles: 0b1010)
    end

    it 'turns a single Symbol into its bitmask' do
      expect(serialize.call(roles: :author)).to eq(roles: 0b100)
    end

    it 'turns an empty array into zero' do
      expect(serialize.call(roles: [])).to eq(roles: 0)
    end

    it 'treats a numeric string as a bitmask' do
      expect(serialize.call(roles: '5')).to eq(roles: 5)
    end

    it 'rewrites String keys and keeps them as String keys' do
      string_keyed = { roles: [:admin] }.transform_keys(&:to_s)

      expect(serialize.call(string_keyed)).to eq({ roles: 1 }.transform_keys(&:to_s))
    end

    it 'rewrites the String key of a column whose Symbol key needs no rewriting' do
      expect(serialize.call({ roles: 5, 'roles' => [:admin] })).to eq({ roles: 5, 'roles' => 1 })
    end

    it 'rewrites the String key of a column whose Symbol key is a non-empty Integer array' do
      expect(serialize.call({ roles: [1, 5], 'roles' => [:admin] })).to eq({ roles: [1, 5], 'roles' => 1 })
    end

    it 'does not modify the hash it was given' do
      conditions = { roles: [:admin] }
      serialize.call(conditions)

      expect(conditions).to eq(roles: [:admin])
    end

    it 'rewrites several bitwise columns at once' do
      expect(serialize.call(roles: [:admin], permissions: [:manage])).to eq(roles: 1, permissions: 2)
    end
  end

  context 'with values that need no rewriting' do
    it 'passes an Integer through' do
      expect(serialize.call(roles: 5)).to eq(roles: 5)
    end

    it 'passes nil through' do
      expect(serialize.call(roles: nil)).to eq(roles: nil)
    end

    it 'passes a non-empty Integer array through' do
      expect(serialize.call(roles: [1, 5])).to eq(roles: [1, 5])
    end

    it 'passes non-bitwise columns through' do
      expect(serialize.call(id: 3, name: 'x')).to eq(id: 3, name: 'x')
    end
  end

  context 'with a column whose type is no longer the bitwise type' do
    it 'leaves the value untouched' do
      model.attribute :roles, :integer

      expect(serialize.call(roles: 'garbage')).to eq(roles: 'garbage')
    end
  end

  context 'with unknown flag values' do
    it 'raises UnknownValueError naming the values and the column' do
      expect { serialize.call(roles: %i[admin bogus]) }
        .to raise_error(ActiveRecord::Bitwise::UnknownValueError, 'Unknown bitwise value(s) ["bogus"] for column roles')
    end

    it 'raises for an Integer mixed into a flag array' do
      expect { serialize.call(roles: [1, :admin]) }
        .to raise_error(ActiveRecord::Bitwise::UnknownValueError, 'Unknown bitwise value(s) ["1"] for column roles')
    end
  end

  context 'with the given hash' do
    it 'does not modify it when it is rewritten' do
      conditions = { roles: [:admin] }
      serialize.call(conditions)

      expect(conditions).to eq(roles: [:admin])
    end

    it 'returns a different object when it is rewritten' do
      conditions = { roles: [:admin] }

      expect(serialize.call(conditions)).not_to equal(conditions)
    end

    it 'returns the very same object when nothing needs rewriting' do
      conditions = { roles: 1, id: 2 }

      expect(serialize.call(conditions)).to equal(conditions)
    end
  end

  context 'with an Integer for one column and flags for the next' do
    it 'still rewrites the flags' do
      expect(serialize.call(roles: 1, permissions: [:manage])).to eq(roles: 1, permissions: 2)
    end
  end

  context 'with an unknown value that is not a String' do
    it 'names it as a String in the error' do
      stamped = with_raw_marker([:bogus], 0).freeze

      expect { serialize.call(roles: stamped) }
        .to raise_error(ActiveRecord::Bitwise::UnknownValueError, 'Unknown bitwise value(s) ["bogus"] for column roles')
    end
  end
end
