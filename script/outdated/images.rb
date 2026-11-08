# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'sorbet-runtime'
require_relative 'network'
require_relative 'report'
require_relative 'workflows'

module Outdated
  # Every Docker image of the workflows at the current digest of its tag, and a numbered tag at the newest major
  # version of the image.
  class Images
    extend T::Sig

    # A pinned official Docker Hub image: `image: "<name>:<tag>@sha256:<digest>"`.
    PIN = /image: "(?<name>[a-z0-9.-]+):(?<tag>[\w.-]+)@(?<digest>sha256:\h{64})"/
    # The manifest types of a multi-platform image, whose digest the pins name.
    MANIFESTS = 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json'
    private_constant :PIN, :MANIFESTS

    # The registry URL of an official Docker Hub image.
    # @param name [String] e.g. "postgres"
    # @return [String]
    sig { params(name: String).returns(String) }
    def self.registry(name)
      "https://registry-1.docker.io/v2/library/#{name}"
    end

    # The headers that authorize reading an official Docker Hub image, with an anonymous token.
    # @param name [String]
    # @return [Hash{Symbol => String}]
    sig { params(name: String).returns(T::Hash[Symbol, String]) }
    def self.headers(name)
      url = "https://auth.docker.io/token?service=registry.docker.io&scope=repository:library/#{name}:pull"
      { Authorization: "Bearer #{Network.dig(Network.json(url), 'token')}" }
    end

    # The digest a tag of an image currently points at.
    # @param name [String]
    # @param tag [String]
    # @param headers [Hash{Symbol => String}] The authorization.
    # @return [String]
    sig { params(name: String, tag: String, headers: T::Hash[Symbol, String]).returns(String) }
    def self.digest(name, tag, headers)
      url = "#{registry(name)}/manifests/#{tag}"
      Network.response(Net::HTTP::Head, url, headers.merge(Accept: MANIFESTS))['docker-content-digest'].to_s
    end

    # The numbered tags of an image (its major versions).
    # @param name [String]
    # @param headers [Hash{Symbol => String}] The authorization.
    # @return [Array<String>]
    sig { params(name: String, headers: T::Hash[Symbol, String]).returns(T::Array[String]) }
    def self.majors(name, headers)
      Network.strings(Network.json("#{registry(name)}/tags/list?n=100000", headers), 'tags').grep(/\A\d+\z/)
    end

    # Creates the check, which records its verdicts in +report+.
    # @param report [Outdated::Report]
    sig { params(report: Report).void }
    def initialize(report)
      @report = report
    end

    # Compares every pinned image with its registry.
    # @return [void]
    sig { void }
    def check
      Workflows.scan(PIN).each { |name, tag, digest| check_pin(name.to_s, tag.to_s, digest.to_s) }
    end

    private

    # Compares one pinned image with its registry: a numbered tag with the newest major version, and the pinned
    # digest with the current digest of the tag.
    # @param name [String] e.g. "postgres"
    # @param tag [String] e.g. "18"
    # @param digest [String] The pinned digest.
    # @return [void]
    sig { params(name: String, tag: String, digest: String).void }
    def check_pin(name, tag, digest)
      headers = Images.headers(name)
      @report.compare("image #{name}", tag, Network.newest(Images.majors(name, headers))) if tag.match?(/\A\d+\z/)
      @report.compare("image #{name}:#{tag} digest", digest, Images.digest(name, tag, headers))
    end
  end
end
