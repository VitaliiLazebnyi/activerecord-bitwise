# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::RelationExtension, '#where' do
  include_context 'with scope fixtures'

  # Decision table: value given for the bitwise column -> fixtures matched (exact bitmask).
  [
    [[:admin], %i[admin]],
    [%i[admin author], %i[both]],
    [%i[author admin], %i[both]],
    [%i[admin author subscriber], %i[three]],
    [%w[admin author], %i[both]],
    [:admin, %i[admin]],
    ['admin', %i[admin]],
    [[], %i[none]],
    [0, %i[none]],
    [1, %i[admin]],
    [5, %i[both]],
    [[1, 5], %i[admin both]],
    ['5', %i[both]],
    [nil, []]
  ].each do |value, expected|
    it "matches #{expected.inspect} for roles: #{value.inspect}" do
      expect(names_in.call(model.where(roles: value))).to eq(expected)
    end
  end

  context 'when the attribute type of a bitwise column is not the bitwise type' do
    before do
      integer_types = { roles: ActiveRecord::Type::Integer.new }.transform_keys(&:to_s)
      allow(model).to receive(:attribute_types).and_return(integer_types)
    end

    it 'leaves the condition to ActiveRecord' do
      expect(model.where(roles: 'garbage').to_sql).to end_with('= NULL')
    end
  end

  context 'with a String key' do
    it 'serializes the value the same way' do
      string_keyed = { roles: [:admin] }.transform_keys(&:to_s)

      expect(names_in.call(model.where(string_keyed))).to eq(%i[admin])
    end
  end

  context 'with several conditions' do
    it 'serializes every bitwise column' do
      model.create!(roles: [:admin], permissions: [:manage])

      expect(model.where(roles: [:admin], permissions: [:manage]).count).to eq(1)
    end

    it 'combines bitwise and ordinary columns' do
      expect(model.where(roles: [:admin], id: fixtures[:admin].id).count).to eq(1)
    end

    it 'can be chained' do
      expect(names_in.call(model.where(roles: %i[admin author]).where(id: fixtures[:both].id))).to eq(%i[both])
    end
  end

  context 'with an unknown flag' do
    it 'raises UnknownValueError instead of silently matching zero' do
      expect { model.where(roles: %i[admin bogus]) }.to raise_error(
        ActiveRecord::Bitwise::UnknownValueError, 'Unknown bitwise value(s) ["bogus"] for column roles'
      )
    end

    it 'raises for an Integer mixed into a flag array' do
      expect { model.where(roles: [1, :admin]) }.to raise_error(
        ActiveRecord::Bitwise::UnknownValueError, 'Unknown bitwise value(s) ["1"] for column roles'
      )
    end
  end

  context 'with conditions that are not bitwise' do
    it 'leaves a SQL string with bind values alone' do
      expect(names_in.call(model.where('roles = ?', 1))).to eq(%i[admin])
    end

    it 'leaves ordinary column conditions alone' do
      expect(names_in.call(model.where(id: fixtures[:author].id))).to eq(%i[author])
    end

    it 'leaves the given hash unmodified' do
      conditions = { roles: [:admin] }
      model.where(conditions)

      expect(conditions).to eq(roles: [:admin])
    end
  end

  context 'with a model without bitwise columns' do
    it 'behaves like plain ActiveRecord' do
      plain = build_model

      expect(plain.where(id: fixtures[:admin].id).count).to eq(1)
    end
  end

  context 'with a column whose type was replaced after declaring it bitwise' do
    it 'leaves the condition to the new type' do
      model.attribute :roles, :integer

      expect(names_in.call(model.where(roles: 1))).to eq(%i[admin])
    end
  end

  context 'with other query methods' do
    it 'supports find_by' do
      expect(model.find_by(roles: %i[admin author])).to eq(fixtures[:both])
    end

    it 'supports exists?' do
      expect(model.exists?(roles: [:author])).to be(true)
    end

    it 'supports uniqueness validations scoped to a bitwise column' do
      unique = build_model { validates :name, uniqueness: { scope: :roles } }
      unique.bitwise :roles, { admin: 0, author: 2 }
      unique.create!(name: 'Ada', roles: [:admin])

      expect(unique.new(name: 'Ada', roles: [:admin])).not_to be_valid
    end

    it 'treats a different flag set as unique' do
      unique = build_model { validates :name, uniqueness: { scope: :roles } }
      unique.bitwise :roles, { admin: 0, author: 2 }
      unique.create!(name: 'Ada', roles: [:admin])

      expect(unique.new(name: 'Ada', roles: [:author])).to be_valid
    end
  end

  describe 'generated SQL' do
    it 'compares the column with the exact bitmask' do
      expect(model.where(roles: %i[admin author]).to_sql).to include("#{qualified_column(model)} = 5")
    end

    it 'lets integer arrays through as IN lists' do
      expect(model.where(roles: [1, 5]).to_sql).to include("#{qualified_column(model)} IN (1, 5)")
    end
  end
end
