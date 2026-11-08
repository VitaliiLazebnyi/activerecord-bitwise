# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'sorbet-runtime'
require_relative 'network'
require_relative 'report'
require_relative 'workflows'

module Outdated
  # Every Python linter of tools/requirements.txt at its newest release on PyPI, and every release binary the
  # workflows download at the newest release of its project.
  class Tools
    extend T::Sig

    # A pinned Python package of tools/requirements.txt.
    REQUIREMENT = /^(?<name>[\w.-]+)==(?<version>\S+)/
    # A release binary a workflow downloads: `<NAME>_VERSION: "<version>"`.
    BINARY = /(?<tool>[A-Z]+)_VERSION: "(?<version>[\d.]+)"/
    # The GitHub repository and the release tag prefix of each binary.
    PROJECTS = T.let(
      { GITLEAKS: %w[gitleaks/gitleaks v], LYCHEE: %w[lycheeverse/lychee lychee-v] }.freeze,
      T::Hash[Symbol, [String, String]]
    )
    private_constant :REQUIREMENT, :BINARY, :PROJECTS

    # Creates the check, which records its verdicts in +report+.
    # @param report [Outdated::Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Compares every Python linter and every release binary with its newest release.
    # @raise [KeyError] When a workflow downloads a binary whose project is not known.
    # @return [void]
    sig { void }
    def check
      requirements = File.read(File.join(ROOT, 'tools', 'requirements.txt'))
      requirements.scan(REQUIREMENT).each { |name, pinned| check_python(name.to_s, pinned.to_s) }
      Workflows.scan(BINARY).each { |tool, release| check_binary(tool.to_s, release.to_s) }
    end

    private

    # Compares one Python package with its newest release on PyPI.
    # @param name [String]
    # @param version [String] The pinned version.
    # @return [void]
    sig { params(name: String, version: String).void }
    def check_python(name, version)
      @report.compare(
        "tool #{name}",
        version,
        Network.dig(Network.json("https://pypi.org/pypi/#{name}/json"), 'info', 'version')
      )
    end

    # Compares one release binary with the newest release of its project.
    # @param tool [String] e.g. "GITLEAKS"
    # @param version [String] The pinned version.
    # @raise [KeyError] When the project of the binary is not known.
    # @return [void]
    sig { params(tool: String, version: String).void }
    def check_binary(tool, version)
      repository, prefix = PROJECTS.fetch(tool.to_sym)
      newest = Network.newest(Network.releases(Network.tags(repository).keys, prefix))
      @report.compare("tool #{repository.split('/').last}", version, newest)
    end
  end
end
