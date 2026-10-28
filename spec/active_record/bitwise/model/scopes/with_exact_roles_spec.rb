# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '.with_exact_roles' do
  include_context 'with scope fixtures'

  # Decision table: arguments -> fixtures returned (records having exactly the given flags).
  [
    [[:admin], %i[admin]],
    [[:author], %i[author]],
    [%i[admin author], %i[both]],
    [%i[author admin], %i[both]],
    [[%i[admin author]], %i[both]],
    [%w[admin author], %i[both]],
    [%i[admin admin], %i[admin]],
    [%i[admin author subscriber], %i[three]],
    [[], %i[none]],
    [[[]], %i[none]],
    [[nil], %i[none]],
    [[''], %i[none]],
    [[nil, ''], %i[none]],
    [%i[admin bogus], []],
    [[:bogus], []],
    [[0], []]
  ].each do |arguments, expected|
    it "with #{arguments.inspect} returns #{expected.inspect}" do
      expect(names_in.call(model.with_exact_roles(*arguments))).to eq(expected)
    end
  end

  it 'returns an ActiveRecord::Relation' do
    expect(model.with_exact_roles(:admin)).to be_a(ActiveRecord::Relation)
  end

  context 'with unmapped bits stored in the database' do
    it 'does not match a record whose full bitmask differs' do
      plant_raw_value(fixtures[:admin], 0b1_0000_0001)

      expect(names_in.call(model.with_exact_roles(:admin))).to eq([])
    end
  end

  context 'with a NULL column' do
    it 'does not match the empty set' do
      plant_raw_value(fixtures[:none], nil)

      expect(names_in.call(model.with_exact_roles)).to eq([])
    end
  end

  context 'when the query joins another alias of the same table' do
    it 'qualifies the column so it is not ambiguous' do
      relation = model.joins('INNER JOIN users AS other_users ON other_users.id = users.id').with_exact_roles(:admin)

      expect(names_in.call(relation)).to eq(%i[admin])
    end
  end

  describe 'generated SQL' do
    let(:column) { qualified_column(model) }

    it 'compares the column with the mask' do
      expect(normalized_sql(model.with_exact_roles(:admin, :author).to_sql)).to include("#{column} = 5")
    end

    it 'compares the column with zero when no flag is given' do
      expect(model.with_exact_roles.to_sql).to include("#{column} = 0")
    end

    it 'matches nothing when any flag is unknown' do
      expect(model.with_exact_roles(:admin, :bogus).to_sql).to include('1=0')
    end
  end
end
