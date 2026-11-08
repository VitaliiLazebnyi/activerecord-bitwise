# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'sorbet-runtime'
require_relative 'network'
require_relative 'report'
require_relative 'workflows'

module Outdated
  # Every action of the workflows at its newest release, pinned to the commit of that release's tag.
  class Actions
    extend T::Sig

    # A pinned action: `uses: "<owner>/<repository>[/<path>]@<commit>"  # <tag>`.
    PIN = %r{uses: "(?<repository>[\w.-]+/[\w.-]+)[\w./-]*@(?<commit>\h{40})" +# (?<tag>v[\d.]+)}
    private_constant :PIN

    # Creates the check, which records its verdicts in +report+.
    # @param report [Outdated::Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Compares every pinned action with the newest release of its repository.
    # @return [void]
    sig { void }
    def check
      Workflows.scan(PIN).each { |repository, commit, tag| check_pin(repository.to_s, commit.to_s, tag.to_s) }
    end

    private

    # Compares one pinned action with the newest release of its repository.
    # @param repository [String] e.g. "actions/checkout"
    # @param commit [String] The pinned commit.
    # @param tag [String] The release tag the pin names.
    # @return [void]
    sig { params(repository: String, commit: String, tag: String).void }
    def check_pin(repository, commit, tag)
      tags = Network.tags(repository)
      @report.compare("action #{repository}", tag, "v#{Network.newest(Network.releases(tags.keys, 'v'))}")
      @report.compare("action #{repository} #{tag} commit", commit, tags.fetch(tag, "no tag #{tag}"))
    end
  end
end
