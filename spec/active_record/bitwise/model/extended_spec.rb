# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '.extended' do
  let(:host) { Class.new { extend ActiveRecord::Bitwise::Model } }

  context 'with a class that has no bitwise definitions yet' do
    it 'starts with an empty definitions hash' do
      expect(host.bitwise_definitions).to eq({})
    end

    it 'exposes the definitions to instances too' do
      expect(host.new.bitwise_definitions).to eq({})
    end

    it 'lets the class replace its definitions' do
      host.bitwise_definitions = { roles: :configured }

      expect(host.bitwise_definitions).to eq(roles: :configured)
    end
  end

  context 'with a class that is extended again' do
    it 'keeps the definitions it already has' do
      host.bitwise_definitions = { roles: :configured }
      host.extend(described_class)

      expect(host.bitwise_definitions).to eq(roles: :configured)
    end
  end
end
