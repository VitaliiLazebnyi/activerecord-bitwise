# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Definitions do
  include_context 'with a user model'

  describe '.bitwise?' do
    it('is true for a model with the macro') { expect(described_class.bitwise?(model)).to be(true) }
    it('is false for a plain class') { expect(described_class.bitwise?(Class.new)).to be(false) }

    it 'is false for a class that only has an instance method of that name' do
      plain = Class.new { define_method(:bitwise_definitions) { {} } }

      expect(described_class.bitwise?(plain)).to be(false)
    end

    it 'is true for a class that has the method on its singleton class' do
      plain = Class.new { define_singleton_method(:bitwise_definitions) { {} } }

      expect(described_class.bitwise?(plain)).to be(true)
    end
  end

  describe '.mapping' do
    it 'is the mapping of a bitwise attribute' do
      expect(described_class.mapping(model, :roles)).to eq(admin: 0, editor: 1, author: 2, subscriber: 3)
    end

    it 'accepts the attribute as a String' do
      expect(described_class.mapping(model, 'permissions')).to eq(read: 0, manage: 1)
    end

    it('is nil for an attribute that is not bitwise') { expect(described_class.mapping(model, :name)).to be_nil }

    it 'is nil for a class without definitions' do
      expect(described_class.mapping(Class.new, :roles)).to be_nil
    end
  end
end
