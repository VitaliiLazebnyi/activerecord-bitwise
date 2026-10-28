# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::RecursionGuard, '.run' do
  let(:limit_message) { 'System recursion limit exceeded in deserialize' }
  let(:nest) { ->(levels, &block) { levels.zero? ? block.call : described_class.run { nest.call(levels - 1, &block) } } }

  it 'returns the result of the block' do
    expect(described_class.run { :result }).to eq(:result)
  end

  it 'allows one nested call' do
    expect(nest.call(1) { :inner }).to eq(:inner)
  end

  it 'allows two nested calls' do
    expect(nest.call(2) { :inner }).to eq(:inner)
  end

  it 'rejects a third nested call' do
    expect { nest.call(3) { :inner } }.to raise_error(ActiveRecord::Bitwise::Error, limit_message)
  end

  it 'restores the previous depth, not zero, when a nested call returns' do
    described_class.run do
      described_class.run { :first }

      expect { nest.call(2) { :inner } }.to raise_error(ActiveRecord::Bitwise::Error, limit_message)
    end
  end

  it 'restores the depth when the block raises' do
    expect { described_class.run { raise 'boom' } }.to raise_error(RuntimeError, 'boom')

    expect(nest.call(2) { :inner }).to eq(:inner)
  end

  it 'keeps the depth of each thread separate' do
    results = nest.call(2) { Thread.new { nest.call(2) { :other } }.value }

    expect(results).to eq(:other)
  end
end
