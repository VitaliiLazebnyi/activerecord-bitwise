# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '.without_roles' do
  include_context 'with scope fixtures'

  # Decision table: arguments -> fixtures returned (records having NONE of the given flags).
  [
    [[:admin], %i[none author]],
    [[:author], %i[none admin]],
    [%i[admin author], %i[none]],
    [[%i[admin author]], %i[none]],
    [%w[admin author], %i[none]],
    [%i[admin bogus], %i[none author]],
    [[:subscriber], %i[none admin author both]],
    [[:bogus], %i[none admin author both three]],
    [%w[bogus other], %i[none admin author both three]],
    [[], %i[none admin author both three]],
    [[[]], %i[none admin author both three]],
    [[nil], %i[none admin author both three]],
    [[''], %i[none admin author both three]],
    [[0], %i[none admin author both three]]
  ].each do |arguments, expected|
    it "with #{arguments.inspect} returns #{expected.inspect}" do
      expect(names_in.call(model.without_roles(*arguments))).to eq(expected)
    end
  end

  it 'returns an ActiveRecord::Relation' do
    expect(model.without_roles(:admin)).to be_a(ActiveRecord::Relation)
  end

  context 'with unmapped bits stored in the database' do
    it 'ignores them when excluding' do
      plant_raw_value(fixtures[:none], 0b1_0000_0000)

      expect(names_in.call(model.without_roles(:admin))).to eq(%i[none author])
    end
  end

  context 'with a NULL column' do
    it 'excludes the row, because SQL NULL never satisfies a comparison' do
      plant_raw_value(fixtures[:none], nil)

      expect(names_in.call(model.without_roles(:admin))).to eq(%i[author])
    end
  end

  context 'when the query joins another alias of the same table' do
    it 'qualifies the column so it is not ambiguous' do
      relation = model.joins('INNER JOIN users AS other_users ON other_users.id = users.id').without_roles(:admin)

      expect(names_in.call(relation)).to eq(%i[none author])
    end
  end

  describe 'generated SQL' do
    let(:column) { qualified_column(model) }

    it 'tests that no mask bit is set' do
      expect(normalized_sql(model.without_roles(:admin, :author).to_sql)).to include("#{column} & 5 = 0")
    end

    it 'adds no condition when every flag is unknown' do
      expect(model.without_roles(:bogus).to_sql).not_to include('WHERE')
    end
  end
end
