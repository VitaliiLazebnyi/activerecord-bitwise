# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'sorbet-runtime'
require 'yaml'

module Outdated
  # The hold list (script/outdated_holds.yml): the dependencies deliberately kept below their newest release.
  module Holds
    extend T::Sig

    # The sections of the hold list and the label prefix of their entries.
    SECTIONS = T.let(
      { gems: 'gem', actions: 'action', images: 'image', rubies: 'Ruby', tools: 'tool' }.freeze,
      T::Hash[Symbol, String]
    )
    public_constant :SECTIONS

    # The holds of the list, by label: the newest release each one keeps out.
    # @param path [String] The hold list.
    # @raise [ArgumentError] When a hold names no newest release or gives no reason.
    # @return [Hash{String => String}]
    sig { params(path: String).returns(T::Hash[String, String]) }
    def self.load(path)
      document = YAML.safe_load_file(path)
      sections = document.is_a?(Hash) ? document : {}
      SECTIONS.flat_map { |section, prefix| entries(sections.fetch(section.to_s, {}), prefix) }
        .to_h
    end

    # The holds of one section, as [label, newest release] pairs.
    # @param section [Object] The parsed section: a Hash of holds by name.
    # @param prefix [String] The label prefix of the section.
    # @raise [ArgumentError] When a hold names no newest release or gives no reason.
    # @return [Array<Array(String, String)>]
    sig { params(section: Object, prefix: String).returns(T::Array[[String, String]]) }
    def self.entries(section, prefix)
      holds = section.is_a?(Hash) ? section : {}
      holds.map do |name, hold|
        label = "#{prefix} #{name}"
        [label, newest(hold, label)]
      end
    end

    # The newest release a hold keeps out.
    # @param hold [Object] The parsed hold: newest, and blocked_by or reason.
    # @param label [String] The label of the hold, for the error message.
    # @raise [ArgumentError] When the hold names no newest release or gives no reason.
    # @return [String]
    sig { params(hold: Object, label: String).returns(String) }
    def self.newest(hold, label)
      fields = hold.is_a?(Hash) ? hold : {}
      newest = fields['newest'].to_s
      return newest unless newest.empty? || (fields['blocked_by'] || fields['reason']).to_s.strip.empty?

      raise(ArgumentError, "the hold of #{label} needs `newest` and a `blocked_by` or `reason`")
    end
  end
end
