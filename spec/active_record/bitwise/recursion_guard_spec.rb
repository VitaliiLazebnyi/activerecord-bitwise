# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::RecursionGuard do
  describe '.run' do
    it 'returns the value of the block' do
      expect(described_class.run { :result }).to eq(:result)
    end

    it 'allows the block to run nested once' do
      expect(described_class.run { described_class.run { :inner } }).to eq(:inner)
    end

    it 'refuses a third level' do
      expect { described_class.run { described_class.run { described_class.run { nil } } } }
        .to raise_error(ActiveRecord::Bitwise::Error, 'System recursion limit exceeded in deserialize')
    end

    it 'restores the depth after the block, even when it raises' do
      expect { described_class.run { raise 'boom' } }.to raise_error('boom')

      expect(described_class.run { described_class.run { :ok } }).to eq(:ok)
    end

    it 'counts per thread' do
      result = described_class.run { Thread.new { described_class.run { described_class.run { :deep } } }.value }

      expect(result).to eq(:deep)
    end
  end
end
