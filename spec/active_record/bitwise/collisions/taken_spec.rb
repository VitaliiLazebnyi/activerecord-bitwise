# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Collisions::Taken do
  describe '.for' do
    it 'collects the methods generated for the other columns' do
      taken = described_class.for({ roles: { generated_methods: ['a?'] }, perms: { generated_methods: ['b?'] } }, [],
                                  :roles)

      expect([taken.generated?('a?'), taken.generated?('b?')]).to eq([false, true])
    end

    it 'copes with a definition that has no generated methods' do
      taken = described_class.for({ roles: {}, perms: {} }, [], :roles)

      expect(taken.generated?('b?')).to be(false)
    end

    it 'remembers the attributes and definitions that must not be shadowed' do
      taken = described_class.for({ roles: {} }, ['name'], :other)

      expect([taken.shadowing?('name'), taken.shadowing?('roles'), taken.shadowing?('free')]).to eq([true, true, false])
    end
  end

  describe 'core methods' do
    let(:taken) { described_class.for({}, [], :roles) }

    it 'include public instance methods of ActiveRecord::Base' do
      expect(taken.core?('save')).to be(true)
    end

    it 'include private instance methods of ActiveRecord::Base' do
      private_name = (ActiveRecord::Base.private_instance_methods - ActiveRecord::Base.instance_methods).first

      expect(taken.core?(private_name.to_s)).to be(true)
    end

    it 'include protected instance methods of ActiveRecord::Base' do
      allow(ActiveRecord::Base).to receive(:protected_instance_methods).and_return([:guarded_helper])

      expect(described_class.for({}, [], :roles).core?('guarded_helper')).to be(true)
    end

    it 'exclude other names' do
      expect(taken.core?('definitely_not_a_core_method')).to be(false)
    end
  end
end
