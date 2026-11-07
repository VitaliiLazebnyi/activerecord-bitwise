# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#roles=' do
  include_context 'with a user model'

  let(:record) { model.new }

  context 'with flag names' do
    [
      ['Symbols', %i[admin author], %i[admin author]],
      ['Strings', %w[admin author], %i[admin author]],
      ['mixed Symbols and Strings', ['admin', :author], %i[admin author]],
      ['a single Symbol', :author, [:author]],
      ['a single String', 'author', [:author]],
      ['an empty array', [], []],
      ['nil', nil, []],
      ['nil and empty strings among the names', ['', 'admin', nil, 'author'], %i[admin author]],
      ['duplicates', [:admin, 'admin', :admin], [:admin]]
    ].each do |label, assigned, expected_flags|
      it "reads back #{expected_flags.inspect} when assigned #{label}" do
        record.roles = assigned

        expect(record.roles).to eq(expected_flags)
      end
    end

    it 'keeps the order in which the flags were given' do
      record.roles = %i[author admin]

      expect(record.roles).to eq(%i[author admin])
    end
  end

  context 'with an Integer or numeric String bitmask' do
    [
      ['8', 8, [:subscriber]],
      ['0', 0, []],
      ['5 as a String', '5', %i[admin author]],
      ['a bitmask with unmapped bits', 0b1_0000_0001, [:admin]]
    ].each do |label, assigned, expected_flags|
      it "reads back #{expected_flags.inspect} when assigned #{label}" do
        record.roles = assigned

        expect(record.roles).to eq(expected_flags)
      end
    end
  end

  context 'with names that are not in the mapping' do
    it 'holds them as Strings so that validation can report them' do
      record.roles = %i[admin hacker]

      expect(record.roles).to eq([:admin, 'hacker'])
    end

    it 'does not create Symbols from untrusted input' do
      payload = unique_unmapped_name
      record.roles = [payload]

      expect(symbol_exists?(payload)).to be(false)
    end

    it 'does not persist them' do
      record.roles = %i[admin hacker]
      record.save!(validate: false)

      expect(raw_value(record)).to eq(1)
    end
  end

  context 'with an array near the size limit' do
    it 'accepts 100 names' do
      record.roles = Array.new(100) { |i| "name_#{i}" }

      expect(record.roles.size).to eq(100)
    end

    it 'rejects 101 names naming the limit' do
      expect { record.roles = Array.new(101) { |i| "name_#{i}" } }
        .to raise_error(ArgumentError, 'Array size cannot exceed 100')
    end
  end

  context 'with a value that cannot be a flag array' do
    [{ a: 1 }, true, false].each do |uncastable|
      it "rejects #{uncastable.inspect}" do
        expect { record.roles = uncastable }
          .to raise_error(ArgumentError, "cannot cast #{uncastable.inspect} to a bitwise flag array for column roles")
      end
    end

    it 'leaves the previous flags untouched after a rejected assignment' do
      record.roles = [:admin]
      capture_error { record.roles = true }

      expect(record.roles).to eq([:admin])
    end
  end

  context 'when persisted' do
    [
      ['no flags', [], 0],
      ['the first bit', [:admin], 0b0001],
      ['the last mapped bit', [:subscriber], 0b1000],
      ['several flags', %i[admin subscriber], 0b1001],
      ['every flag', %i[admin editor author subscriber], 0b1111]
    ].each do |label, flags, expected_bitmask|
      it "stores #{expected_bitmask} for #{label}" do
        record.roles = flags
        record.save!

        expect(raw_value(record)).to eq(expected_bitmask)
      end
    end

    it 'stores NULL when assigned nil' do
      record.roles = nil
      record.save!

      expect(raw_value(record)).to be_nil
    end

    it 'stores an assigned Integer verbatim, including unmapped bits' do
      record.roles = 0b10_0001
      record.save!

      expect(raw_value(record)).to eq(0b10_0001)
    end

    it 'reads the same flags back after reloading' do
      record.roles = %i[admin author]
      record.save!

      expect(record.reload.roles).to eq(%i[admin author])
    end
  end
end
