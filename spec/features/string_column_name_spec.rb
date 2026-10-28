# typed: false
# frozen_string_literal: true

RSpec.describe 'Declaring a bitwise column by its String name' do
  let(:model) { build_model { bitwise 'roles', { admin: 0, author: 1 } } }
  let!(:record) { model.create!(roles: [:admin]) }

  it 'registers the definition under the Symbol name' do
    expect(model.bitwise_definitions.keys).to eq([:roles])
  end

  it 'reads the flags' do
    expect(model.find(record.id).roles).to eq([:admin])
  end

  it 'defines the flag predicates' do
    expect(record.admin?).to be(true)
  end

  it 'defines the scopes' do
    expect(model.with_roles(:admin).to_a).to eq([record])
  end

  it 'adds a flag atomically on the instance' do
    record.add_role!(:author)

    expect(record.roles).to eq(%i[admin author])
  end

  it 'adds a flag atomically for records' do
    model.add_roles!(:author, records: record)

    expect(raw_value(record)).to eq(0b11)
  end

  it 'removes a flag atomically on the instance' do
    record.remove_role!(:admin)

    expect(record.roles).to eq([])
  end

  it 'persists flags assigned through the setter' do
    record.update!(roles: %i[admin author])

    expect(raw_value(record)).to eq(0b11)
  end

  it 'keeps unmapped bits when a flag array is assigned' do
    plant_raw_value(record, 0b101)
    record.roles = %i[admin author]
    record.save!

    expect(raw_value(record)).to eq(0b111)
  end

  it 'validates the column against the table' do
    expect { build_model { bitwise 'name', { admin: 0 } }.new }
      .to raise_error(ArgumentError, 'Bitwise column name must be an integer database column')
  end
end
