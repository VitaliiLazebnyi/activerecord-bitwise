# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#bitwise' do
  include_context 'with a user model'

  let(:bitwise_callbacks) do
    lambda do |callbacks|
      callbacks.select { |callback| callback.filter.to_s.include?('bitwise') }
    end
  end

  context 'with several bitwise columns' do
    it 'registers one initialization callback' do
      expect(bitwise_callbacks.call(model._initialize_callbacks).size).to eq(1)
    end

    it 'registers no save callback' do
      expect(bitwise_callbacks.call(model._save_callbacks)).to be_empty
    end
  end

  context 'with a subclass that declares another column' do
    let(:child) { build_model(parent: model) { bitwise :custom_limits, { guest: 0 } } }

    it 'does not register the initialization callback again' do
      expect(bitwise_callbacks.call(child._initialize_callbacks).size).to eq(1)
    end
  end
end
