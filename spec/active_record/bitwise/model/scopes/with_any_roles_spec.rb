# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '.with_any_roles' do
  include_context 'with scope fixtures'

  # Decision table: arguments -> fixtures returned (records having ANY of the given flags).
  [
    [[:admin], %i[admin both three]],
    [%i[author subscriber], %i[author both three]],
    [[%i[author subscriber]], %i[author both three]],
    [%w[author subscriber], %i[author both three]],
    [%i[admin author], %i[admin author both three]],
    [%i[author bogus], %i[author both three]],
    [[:bogus], []],
    [%w[bogus other], []],
    [[0], []],
    [[], %i[none admin author both three]],
    [[[]], %i[none admin author both three]],
    [[nil], %i[none admin author both three]],
    [[''], %i[none admin author both three]],
    [[nil, ''], %i[none admin author both three]]
  ].each do |arguments, expected|
    it "with #{arguments.inspect} returns #{expected.inspect}" do
      expect(names_in.call(model.with_any_roles(*arguments))).to eq(expected)
    end
  end

  it 'returns an ActiveRecord::Relation' do
    expect(model.with_any_roles(:admin)).to be_a(ActiveRecord::Relation)
  end

  context 'with unmapped bits stored in the database' do
    it 'still matches on the mapped bits' do
      plant_raw_value(fixtures[:admin], 0b1_0000_0001)

      expect(names_in.call(model.with_any_roles(:admin))).to eq(%i[admin both three])
    end

    it 'does not match a record that has only unmapped bits' do
      plant_raw_value(fixtures[:none], 0b1_0000_0000)

      expect(names_in.call(model.with_any_roles(:admin, :author))).to eq(%i[admin author both three])
    end
  end

  context 'with a NULL column' do
    it 'does not match' do
      plant_raw_value(fixtures[:admin], nil)

      expect(names_in.call(model.with_any_roles(:admin))).to eq(%i[both three])
    end
  end

  context 'when the query joins another alias of the same table' do
    it 'qualifies the column so it is not ambiguous' do
      relation = model.joins('INNER JOIN users AS other_users ON other_users.id = users.id').with_any_roles(:admin)

      expect(names_in.call(relation)).to eq(%i[admin both three])
    end
  end

  describe 'generated SQL' do
    let(:column) { qualified_column(model) }

    it 'tests that any mask bit is set' do
      expect(model.with_any_roles(:admin, :author).to_sql).to include("#{column} & 5 > 0")
    end

    it 'matches nothing when every flag is unknown' do
      expect(model.with_any_roles(:bogus).to_sql).to include('1=0')
    end
  end
end
