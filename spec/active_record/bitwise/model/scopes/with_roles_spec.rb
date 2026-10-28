# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '.with_roles' do
  include_context 'with scope fixtures'

  context 'with a flag whose name is numeric' do
    let(:model) { build_model { bitwise :roles, { '5': 0, other: 1 } } }

    it 'finds records by a numeric argument' do
      flagged = model.create!(roles: [:'5'])
      model.create!(roles: [:other])

      expect(model.with_roles(5).to_a).to eq([flagged])
    end
  end

  # Decision table: arguments -> fixtures returned (records having ALL the given flags).
  [
    [[:admin], %i[admin both three]],
    [[:author], %i[author both three]],
    [[:subscriber], %i[three]],
    [%i[admin author], %i[both three]],
    [[%i[admin author]], %i[both three]],
    [%w[admin author], %i[both three]],
    [%i[admin admin], %i[admin both three]],
    [%i[admin author subscriber], %i[three]],
    [%i[admin bogus], %i[admin both three]],
    [[:bogus], []],
    [%w[bogus other], []],
    [[], %i[none admin author both three]],
    [[[]], %i[none]],
    [[nil], %i[none]],
    [[''], %i[none]],
    [[nil, ''], %i[none]],
    [[0], %i[none]],
    [%w[0], %i[none]],
    [[:admin, 0], %i[none]]
  ].each do |arguments, expected|
    it "with #{arguments.inspect} returns #{expected.inspect}" do
      expect(names_in.call(model.with_roles(*arguments))).to eq(expected)
    end
  end

  it 'returns an ActiveRecord::Relation' do
    expect(model.with_roles(:admin)).to be_a(ActiveRecord::Relation)
  end

  it 'returns a relation even without arguments' do
    expect(model.with_roles).to be_a(ActiveRecord::Relation)
  end

  context 'with unmapped bits stored in the database' do
    it 'still matches on the mapped bits' do
      plant_raw_value(fixtures[:admin], 0b1_0000_0001)

      expect(names_in.call(model.with_roles(:admin))).to eq(%i[admin both three])
    end
  end

  context 'with a NULL column and the empty set (0)' do
    it 'matches, because a NULL column reads as no flags' do
      plant_raw_value(fixtures[:none], nil)

      expect(names_in.call(model.with_roles(0))).to eq(%i[none])
    end
  end

  context 'with a NULL column' do
    it 'does not match' do
      plant_raw_value(fixtures[:admin], nil)

      expect(names_in.call(model.with_roles(:admin))).to eq(%i[both three])
    end
  end

  context 'when chained with another scope' do
    it 'intersects both conditions' do
      expect(names_in.call(model.with_roles(:admin).without_roles(:author))).to eq(%i[admin])
    end
  end

  context 'when the query joins another alias of the same table' do
    it 'qualifies the column so it is not ambiguous' do
      relation = model.joins('INNER JOIN users AS other_users ON other_users.id = users.id').with_roles(:admin)

      expect(names_in.call(relation)).to eq(%i[admin both three])
    end
  end

  describe 'generated SQL' do
    let(:column) { qualified_column(model) }

    it 'tests that all mask bits are set' do
      expect(normalized_sql(model.with_roles(:admin, :author).to_sql)).to include("#{column} & 5 = 5")
    end

    it 'tests for zero when no flag is given' do
      expect(model.with_roles([]).to_sql).to include("(#{column} = 0 OR #{column} IS NULL)")
    end

    it 'matches nothing when every flag is unknown' do
      expect(model.with_roles(:bogus).to_sql).to include('1=0')
    end
  end
end
