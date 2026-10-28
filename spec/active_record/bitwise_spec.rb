# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise do
  describe 'constants' do
    it 'caps assigned arrays at 100 elements' do
      expect(described_class::MAX_ARRAY_SIZE).to eq(100)
    end

    it 'allows bit positions up to 62' do
      expect(described_class::MAX_BIT_POSITION).to eq(62)
    end

    it 'declares a semantic version' do
      expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe 'error classes' do
    [
      [ActiveRecord::Bitwise::Error, StandardError],
      [ActiveRecord::Bitwise::NotSupportedError, ActiveRecord::Bitwise::Error],
      [ActiveRecord::Bitwise::ConfigurationError, ArgumentError],
      [ActiveRecord::Bitwise::UnknownValueError, ArgumentError]
    ].each do |error_class, ancestor|
      it "makes #{error_class} a kind of #{ancestor}" do
        expect(error_class.ancestors).to include(ancestor)
      end
    end
  end
end
