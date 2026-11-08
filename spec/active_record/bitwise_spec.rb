# typed: true
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

RSpec.describe(ActiveRecord::Bitwise) do
  describe 'constants' do
    it 'caps assigned arrays at 100 elements' do
      expect(ActiveRecord::Bitwise::MAX_ARRAY_SIZE).to(eq(100))
    end

    it 'allows bit positions up to 62' do
      expect(ActiveRecord::Bitwise::MAX_BIT_POSITION).to(eq(62))
    end

    it 'declares a semantic version' do
      expect(ActiveRecord::Bitwise::VERSION).to(match(/\A\d+\.\d+\.\d+/))
    end
  end

  describe 'error classes' do
    let(:error_classes) do
      [
        [ActiveRecord::Bitwise::Error, StandardError],
        [ActiveRecord::Bitwise::NotSupportedError, ActiveRecord::Bitwise::Error],
        [ActiveRecord::Bitwise::ConfigurationError, ArgumentError],
        [ActiveRecord::Bitwise::UnknownValueError, ArgumentError]
      ]
    end

    it 'derives every error class from its documented ancestor', :aggregate_failures do
      error_classes.each do |error_class, ancestor|
        aggregate_failures("makes #{error_class} a kind of #{ancestor}") do
          expect(error_class.ancestors).to(include(ancestor))
        end
      end
    end
  end
end
