# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'open3'
require 'sorbet-runtime'
require_relative 'error'
require_relative 'report'

module Outdated
  # Every gem of Gemfile.lock, every group included, at its newest release (`bundle outdated`).
  class Bundle
    extend T::Sig

    # A line of `bundle outdated --parseable`.
    OUTDATED = /^(?<name>\S+) \(newest (?<newest>[^,\s]+), installed (?<installed>[^,)\s]+)/
    private_constant :OUTDATED

    # The outdated gems: name, installed version and newest release.
    # @raise [Outdated::Error] When `bundle outdated` cannot check the gems.
    # @return [Array<Array(String, String, String)>]
    sig { returns(T::Array[[String, String, String]]) }
    def self.outdated
      # CI installs the bundle in deployment mode, in which `bundle outdated` refuses to run.
      unfrozen = %w[env BUNDLE_DEPLOYMENT=false BUNDLE_FROZEN=false]
      output, status = Open3.capture2e(*unfrozen, 'bundle', 'outdated', '--parseable', chdir: ROOT)
      # `bundle outdated` exits with 1 when it finds outdated gems; any other failure means it could not check them.
      raise(Error, "bundle outdated failed (#{status}):\n#{output}") unless status.success? || status.exitstatus == 1

      output.scan(OUTDATED).map { |name, newest, installed| [name.to_s, installed.to_s, newest.to_s] }
    end

    # Creates the check, which records its verdicts in +report+.
    # @param report [Outdated::Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Compares every outdated gem with its newest release.
    # @raise [Outdated::Error] When `bundle outdated` cannot check the gems.
    # @return [void]
    sig { void }
    def check
      Bundle.outdated.each { |name, installed, newest| @report.compare("gem #{name}", installed, newest) }
    end
  end
end
