# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'json'
require 'net/http'
require 'open3'
require 'sorbet-runtime'
require 'uri'
require_relative 'error'

module Outdated
  # Reads the newest releases from the network: HTTP APIs and the tags of git repositories.
  module Network
    extend T::Sig

    # The body of a successful GET request.
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @raise [Outdated::Error] When the server does not answer with a success.
    # @return [String]
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(String) }
    def self.body(url, headers = {})
      response = response(Net::HTTP::Get, url, headers)
      raise(Error, "GET #{url}: HTTP #{response.code}") unless response.is_a?(Net::HTTPSuccess)

      response.body.to_s
    end

    # The response to a request.
    # @param request_class [Class] e.g. Net::HTTP::Get
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Net::HTTPResponse]
    sig do
      params(request_class: T.class_of(Net::HTTPRequest), url: String, headers: T::Hash[Symbol, String])
        .returns(Net::HTTPResponse)
    end
    def self.response(request_class, url, headers)
      uri = URI.parse(url)
      request = request_class.new(uri, headers)
      Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    end

    # The parsed JSON body of a successful GET request.
    # @param url [String]
    # @param headers [Hash{Symbol => String}]
    # @return [Object]
    sig { params(url: String, headers: T::Hash[Symbol, String]).returns(Object) }
    def self.json(url, headers = {})
      JSON.parse(body(url, headers))
    end

    # The value at +path+ of a parsed JSON document, as a String.
    # @param document [Object]
    # @param path [Array<String>]
    # @return [String] Empty when there is no such value.
    sig { params(document: Object, path: String).returns(String) }
    def self.dig(document, *path)
      node(document, path).to_s
    end

    # The Strings of the Array at +path+ of a parsed JSON document.
    # @param document [Object]
    # @param path [Array<String>]
    # @return [Array<String>] Empty when there is no such Array.
    sig { params(document: Object, path: String).returns(T::Array[String]) }
    def self.strings(document, *path)
      Array(node(document, path)).map(&:to_s)
    end

    # The node at +path+ of a parsed JSON document.
    # @param document [Object]
    # @param path [Array<String>]
    # @return [Object, nil]
    sig { params(document: Object, path: T::Array[String]).returns(T.nilable(Object)) }
    def self.node(document, path)
      path.reduce(document) { |acc, elem| acc[elem] if acc.is_a?(Hash) }
    end

    # The tags of a GitHub repository and the commit each one points at (annotated tags peeled).
    # @param repository [String] e.g. "actions/checkout"
    # @raise [Outdated::Error] When git cannot list them.
    # @return [Hash{String => String}]
    sig { params(repository: String).returns(T::Hash[String, String]) }
    def self.tags(repository)
      output, status = Open3.capture2('git', 'ls-remote', '--tags', "https://github.com/#{repository}")
      raise(Error, "git ls-remote #{repository} failed") unless status.success?

      # `git ls-remote` lists an annotated tag twice: the tag object, then (as `<tag>^{}`) its commit, which wins.
      output.lines.to_h do |line|
        commit, ref = line.chomp.split("\t", 2)
        [ref.to_s.delete_prefix('refs/tags/').delete_suffix('^{}'), commit.to_s]
      end
    end

    # The highest of +versions+.
    # @param versions [Array<String>] Release versions, e.g. "1.2.3".
    # @raise [Outdated::Error] When there is none.
    # @return [String]
    sig { params(versions: T::Array[String]).returns(String) }
    def self.newest(versions)
      versions.max_by { |version| Gem::Version.new(version) } || raise(Error, 'no release found')
    end

    # The release versions among +tags+: the ones of the form <prefix><version>.
    # @param tags [Array<String>]
    # @param prefix [String] e.g. "v"
    # @return [Array<String>] The versions, without the prefix.
    sig { params(tags: T::Array[String], prefix: String).returns(T::Array[String]) }
    def self.releases(tags, prefix)
      tags.filter_map { |tag| tag.delete_prefix(prefix) if tag.match?(/\A#{Regexp.escape(prefix)}\d+(\.\d+)*\z/) }
    end
  end
end
