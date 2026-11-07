#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Fails when a dependency of the repository is not at its newest release and is not on the documented hold list
# (script/outdated_holds.yml), or when a listed hold is no longer needed. It covers the gems of Gemfile.lock (every
# group, the optional ones included), the GitHub Actions of the workflows (release tag and commit), the Docker images
# of the workflows (newest major version and the digest of their tag), every pinned Ruby (the newest patch release of
# its line, and the newest line in .ruby-version), the Python linters of tools/requirements.txt and the release
# binaries the workflows download.
#
# Usage: bundle exec rake outdated (needs the network)

require 'sorbet-runtime'
require_relative 'outdated/actions'
require_relative 'outdated/bundle'
require_relative 'outdated/holds'
require_relative 'outdated/images'
require_relative 'outdated/report'
require_relative 'outdated/rubies'
require_relative 'outdated/tools'

# The outdated check (see the comment at the top of this file).
module Outdated
  extend T::Sig

  # Runs every check and returns the exit status: 0 when every dependency is current or held.
  # @return [Integer]
  sig { returns(Integer) }
  def self.run
    holds = Holds.load(File.join(ROOT, 'script', 'outdated_holds.yml'))
    report = Report.new(holds)
    [Bundle, Actions, Images, Rubies, Tools].each { |check| check.new(report).check }
    report.status
  end
end

exit(Outdated.run) if $PROGRAM_NAME == __FILE__
