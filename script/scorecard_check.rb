#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Checks the OpenSSF Scorecard of every dependency a pull request (or a push) adds, like dependency-review-action
# does, but with explicit per-package allowances. The action can only lower its threshold for every package at
# once, so its own Scorecard report is off (.github/dependency-review.yml) and this check runs on its
# `dependency-changes` output instead.
#
# A dependency whose score is below the threshold fails the check, unless .github/dependency-review.yml allows
# that exact package version at that score (or higher), with a written reason. An allowance for a gem that is
# not in Gemfile.lock at that version fails the check as well, so that none outlives its reason.
#
# Usage (the Dependency review job of .github/workflows/security.yml):
#   DEPENDENCY_CHANGES='<JSON>' script/scorecard_check.rb

require 'json'
require 'net/http'
require 'sorbet-runtime'
require 'uri'
require 'yaml'

# The Scorecard check (see the comment at the top of this file).
module ScorecardCheck
  extend T::Sig

  # The repository root.
  ROOT = T.let(File.expand_path('..', __dir__), String)
  # The configuration of the Dependency review job, with the threshold and the allowances.
  CONFIG = T.let(File.join(ROOT, '.github', 'dependency-review.yml'), String)
  # The lockfile whose gem versions the allowances name.
  LOCKFILE = T.let(File.join(ROOT, 'Gemfile.lock'), String)
  # The OpenSSF Scorecard API, by repository.
  SCORECARD_API = 'https://api.securityscorecards.dev/projects/'
  # The deps.dev API, which knows the source repository of a package version.
  DEPS_DEV_API = 'https://api.deps.dev/v3/systems/'
  public_constant :ROOT, :CONFIG, :LOCKFILE, :SCORECARD_API, :DEPS_DEV_API

  # One added dependency and its score.
  class Result
    extend T::Sig

    # The package, as "<ecosystem>/<name>".
    # @return [String]
    sig { returns(String) }
    attr_reader :package

    # The version that was added.
    # @return [String]
    sig { returns(String) }
    attr_reader :version

    # The overall Scorecard score of the package's repository, nil when it has none.
    # @return [Float, nil]
    sig { returns(T.nilable(Float)) }
    attr_reader :score

    # Creates the result of one added dependency.
    # @param package [String] "<ecosystem>/<name>".
    # @param version [String] The added version.
    # @param score [Float, nil] The Scorecard score.
    sig { params(package: String, version: String, score: T.nilable(Float)).void }
    def initialize(package, version, score)
      @package = package
      @version = version
      @score = score
    end

    # The line printed for the dependency.
    # @return [String]
    sig { returns(String) }
    def to_s
      "#{package} #{version}: OpenSSF Scorecard #{score || 'not published'}"
    end

    # The problem of the dependency when it scores below the threshold and no allowance covers it.
    # @param threshold [Float] The lowest acceptable score.
    # @param allowance [Hash{Symbol => Object}, nil] The allowance of the package, if there is one.
    # @return [String, nil]
    sig { params(threshold: Float, allowance: T.nilable(T::Hash[Symbol, Object])).returns(T.nilable(String)) }
    def problem(threshold, allowance)
      scored = score
      return unless scored && scored < threshold
      return if allowance && allowance[:version] == version && scored >= Float(allowance[:score].to_s)

      "#{package} #{version} has an OpenSSF Scorecard of #{scored}, below #{threshold}, " \
        'and no allowance in .github/dependency-review.yml covers it'
    end
  end

  # Runs the check on the `dependency-changes` JSON of dependency-review-action and prints the problems.
  # @param changes_json [String] Empty when the change touches no dependency (the action then sets no output).
  # @return [Integer] The exit status: 0 when the check passes.
  sig { params(changes_json: String).returns(Integer) }
  def self.main(changes_json)
    changes = changes_json.empty? ? [] : JSON.parse(changes_json, symbolize_names: true)
    config = YAML.safe_load_file(CONFIG, symbolize_names: true)
    found = problems(changes, config, File.read(LOCKFILE))
    found.each { |problem| $stdout.puts("::error::#{problem}") }
    found.empty? ? 0 : 1
  end

  # The problems the check finds (an empty list when it passes).
  # @param changes [Array<Hash>] The `dependency-changes` output of dependency-review-action.
  # @param config [Hash] The parsed .github/dependency-review.yml.
  # @param lockfile [String] The content of Gemfile.lock.
  # @return [Array<String>]
  sig do
    params(
      changes: T::Array[T::Hash[Symbol, Object]],
      config: T::Hash[Symbol, Object],
      lockfile: String
    ).returns(T::Array[String])
  end
  def self.problems(changes, config, lockfile)
    allowances = config.fetch(:'scorecard-allowances', nil)
    allowances = {} unless allowances.is_a?(Hash)
    threshold = Float(config.fetch(:'warn-on-openssf-scorecard-level').to_s)
    added(changes).filter_map { |entry| entry.problem(threshold, allowances[entry.package.to_sym]) } +
      allowances.filter_map { |package, allowance| allowance_problem(package.to_s, allowance, lockfile) }
  end

  # The added dependencies with their scores, each printed.
  # @param changes [Array<Hash>] The `dependency-changes` output of dependency-review-action.
  # @return [Array<Result>]
  sig { params(changes: T::Array[T::Hash[Symbol, Object]]).returns(T::Array[Result]) }
  def self.added(changes)
    results = changes.filter_map { |change| result(change) if change[:change_type] == 'added' }
    results.each { |entry| $stdout.puts(entry) }
  end

  # The package, version and score of an added dependency.
  # @param change [Hash] One dependency change.
  # @return [Result]
  sig { params(change: T::Hash[Symbol, Object]).returns(Result) }
  def self.result(change)
    ecosystem = change.fetch(:ecosystem).to_s
    name = change.fetch(:name).to_s
    version = change.fetch(:version).to_s
    repository = repository(ecosystem, name, version, change[:source_repository_url].to_s)
    Result.new("#{ecosystem}/#{name}", version, repository && score(repository))
  end

  # The source repository of a dependency, the way dependency-review-action finds it: the URL GitHub knows,
  # the owner/repository of a GitHub Action, or else the project deps.dev links to that version.
  # @param ecosystem [String] e.g. "rubygems".
  # @param name [String] The package name.
  # @param version [String] The added version.
  # @param url [String] The source repository URL GitHub knows (empty when it knows none).
  # @return [String, nil] e.g. "github.com/jfelchner/ruby-progressbar"
  sig { params(ecosystem: String, name: String, version: String, url: String).returns(T.nilable(String)) }
  def self.repository(ecosystem, name, version, url)
    known = url.delete_prefix('https://')
    return known unless known.empty?
    return "github.com/#{name.split('/').first(2).join('/')}" if ecosystem == 'actions'

    # Gemspec entries name a requirement (e.g. "~> 0.9") instead of a version: deps.dev knows no such version.
    path = "#{ecosystem}/packages/#{URI.encode_uri_component(name)}/versions/#{URI.encode_uri_component(version)}"
    body = get_body("#{DEPS_DEV_API}#{path}")
    project = body && JSON.parse(body, symbolize_names: true).dig(:relatedProjects, 0, :projectKey, :id)
    project&.to_s
  end

  # The overall OpenSSF Scorecard score of a repository.
  # @param repository [String] e.g. "github.com/jfelchner/ruby-progressbar"
  # @return [Float, nil] Nil when the repository has no Scorecard.
  sig { params(repository: String).returns(T.nilable(Float)) }
  def self.score(repository)
    body = get_body("#{SCORECARD_API}#{repository}")
    value = body && JSON.parse(body, symbolize_names: true)[:score]
    Float(value) if value
  end

  # The body of a GET request, or nil when it does not answer with HTTP 200.
  # @param url [String]
  # @return [String, nil]
  sig { params(url: String).returns(T.nilable(String)) }
  def self.get_body(url)
    response = Net::HTTP.get_response(URI.parse(url))
    response.body.to_s if response.is_a?(Net::HTTPOK)
  end

  # The problem of one allowance: it gives no reason, or names a gem version Gemfile.lock no longer has.
  # @param package [String] e.g. "rubygems/ruby-progressbar"
  # @param allowance [Hash{Symbol => Object}]
  # @param lockfile [String] The content of Gemfile.lock.
  # @return [String, nil]
  sig { params(package: String, allowance: T::Hash[Symbol, Object], lockfile: String).returns(T.nilable(String)) }
  def self.allowance_problem(package, allowance, lockfile)
    return "the allowance for #{package} gives no reason" if allowance[:reason].to_s.strip.empty?

    ecosystem, name = package.split('/', 2)
    version = allowance[:version]
    return if ecosystem != 'rubygems' || lockfile.include?("\n    #{name} (#{version})")

    "the allowance for #{package} #{version} is stale: Gemfile.lock no longer has that version"
  end
end

exit(ScorecardCheck.main(ENV.fetch('DEPENDENCY_CHANGES'))) if $PROGRAM_NAME == __FILE__
