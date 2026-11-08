# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'sorbet-runtime'
require_relative 'report'

module Outdated
  # The GitHub workflows of the repository, where actions, images, Rubies and tools are pinned.
  module Workflows
    extend T::Sig

    # The text of every workflow.
    # @return [Array<String>]
    sig { returns(T::Array[String]) }
    def self.texts
      Dir.glob(File.join(ROOT, '.github', 'workflows', '*.yml')).map { |path| File.read(path) }
    end

    # The captures of every match of +pattern+ in the workflows, without repetitions.
    # @param pattern [Regexp]
    # @return [Array<Array<String>>]
    sig { params(pattern: Regexp).returns(T::Array[T::Array[String]]) }
    def self.scan(pattern)
      matches = texts.flat_map { |text| captures(text, pattern) }
      matches.uniq!
      matches
    end

    # The captures of every match of +pattern+ in +text+.
    # @param text [String]
    # @param pattern [Regexp]
    # @return [Array<Array<String>>]
    sig { params(text: String, pattern: Regexp).returns(T::Array[T::Array[String]]) }
    def self.captures(text, pattern)
      text.scan(pattern).map { |captures| Array(captures).map(&:to_s) }
    end
  end
end
