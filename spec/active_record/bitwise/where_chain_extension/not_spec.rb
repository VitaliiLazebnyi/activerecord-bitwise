# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::WhereChainExtension, '#not' do
  include_context 'with scope fixtures'

  # Decision table: value given for the bitwise column -> fixtures NOT matching that exact bitmask.
  [
    [[:admin], %i[none author both three]],
    [%i[admin author], %i[none admin author three]],
    [%w[admin author], %i[none admin author three]],
    [:admin, %i[none author both three]],
    [[], %i[admin author both three]],
    [1, %i[none author both three]],
    [[1, 5], %i[none author three]],
    ['5', %i[none admin author three]]
  ].each do |value, expected|
    it "matches #{expected.inspect} for roles: #{value.inspect}" do
      expect(names_in.call(model.where.not(roles: value))).to eq(expected)
    end
  end

  context 'with nil' do
    it 'matches every row that is not NULL' do
      expect(names_in.call(model.where.not(roles: nil))).to eq(%i[none admin author both three])
    end
  end

  context 'with a String key' do
    it 'serializes the value the same way' do
      string_keyed = { roles: [:admin] }.transform_keys(&:to_s)

      expect(names_in.call(model.where.not(string_keyed))).to eq(%i[none author both three])
    end
  end

  context 'with an unknown flag' do
    it 'raises UnknownValueError' do
      expect { model.where.not(roles: [:bogus]) }.to raise_error(
        ActiveRecord::Bitwise::UnknownValueError, 'Unknown bitwise value(s) ["bogus"] for column roles'
      )
    end
  end

  context 'with conditions that are not bitwise' do
    it 'leaves ordinary column conditions alone' do
      expect(names_in.call(model.where.not(id: fixtures[:admin].id))).to eq(%i[none author both three])
    end

    it 'leaves a SQL string alone' do
      expect(names_in.call(model.where.not('roles = 0'))).to eq(%i[admin author both three])
    end
  end

  context 'with a model without bitwise columns' do
    it 'behaves like plain ActiveRecord' do
      expect(build_model.where.not(id: fixtures[:admin].id).count).to eq(4)
    end
  end

  context 'with a column whose type was replaced after declaring it bitwise' do
    it 'leaves the condition to the new type' do
      model.attribute :roles, :integer

      expect(names_in.call(model.where.not(roles: 1))).to eq(%i[none author both three])
    end
  end

  describe 'generated SQL' do
    it 'compares the column with the exact bitmask' do
      expect(model.where.not(roles: [:admin]).to_sql).to include("#{qualified_column(model)} != 1")
    end
  end
end
