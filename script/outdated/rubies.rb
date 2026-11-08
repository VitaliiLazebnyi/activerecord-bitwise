# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'sorbet-runtime'
require_relative 'network'
require_relative 'report'
require_relative 'workflows'

module Outdated
  # Every pinned Ruby at the newest patch release of its line, and .ruby-version on the newest line.
  class Rubies
    extend T::Sig

    # A Ruby the workflows pin: `ruby-version: "<v>"`, `ruby: "<v>"`, an item of a `ruby:` matrix list
    # (`- "<v>"`) or the argument of script/check_ruby.sh.
    PIN = /(?:ruby-version: |ruby: |^ +- |check_ruby\.sh )"?(?<version>\d+\.\d+\.\d+)"?$/
    # A release of the index of ruby-lang.org.
    RELEASE = /^ruby-(?<version>\d+\.\d+\.\d+)\t/
    private_constant :PIN, :RELEASE

    # Creates the check, which records its verdicts in +report+.
    # @param report [Outdated::Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
      index = Network.body('https://cache.ruby-lang.org/pub/ruby/index.txt')
      releases = index.scan(RELEASE).flatten.map!(&:to_s)
      releases.uniq!
      @releases = T.let(releases, T::Array[String])
    end

    # Compares every pinned Ruby with the newest release of its line, and .ruby-version with the newest Ruby.
    # @return [void]
    sig { void }
    def check
      primary = File.read(File.join(ROOT, '.ruby-version')).strip
      @report.compare('Ruby (.ruby-version)', primary, Network.newest(@releases))
      [primary, *Workflows.scan(PIN).flatten].uniq.each { |version| check_pin(version) }
    end

    private

    # Compares one pinned Ruby with the newest release of its line.
    # @param version [String] e.g. "3.4.12"
    # @return [void]
    sig { params(version: String).void }
    def check_pin(version)
      line = version[/\A\d+\.\d+/].to_s
      @report.compare(
        "Ruby #{line}",
        version,
        Network.newest(
          @releases.select do |release|
            release.start_with?("#{line}.")
          end
        )
      )
    end
  end
end
