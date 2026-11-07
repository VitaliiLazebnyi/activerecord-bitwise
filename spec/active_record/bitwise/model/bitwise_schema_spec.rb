# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#bitwise_schema' do
  include_context 'with a user model'

  it 'returns the bit positions of a Hash mapping' do
    expect(model.bitwise_schema(:roles)).to eq(admin: 0, editor: 1, author: 2, subscriber: 3)
  end

  it 'returns the index as bit position for an Array mapping' do
    expect(model.bitwise_schema(:legacy_roles)).to eq(admin: 0, moderator: 1, author: 2, subscriber: 3)
  end

  it 'accepts the column name as a String' do
    expect(model.bitwise_schema('permissions')).to eq(read: 0, manage: 1)
  end

  it 'returns nil for a column that is not bitwise' do
    expect(model.bitwise_schema(:name)).to be_nil
  end

  it 'returns nil for a column that does not exist' do
    expect(model.bitwise_schema(:missing)).to be_nil
  end

  it 'returns a copy that callers can modify without affecting the model' do
    model.bitwise_schema(:roles)[:hacked] = 99

    expect(model.bitwise_schema(:roles)).to eq(admin: 0, editor: 1, author: 2, subscriber: 3)
  end

  it 'returns a new object on every call' do
    expect(model.bitwise_schema(:roles)).not_to equal(model.bitwise_schema(:roles))
  end
end
