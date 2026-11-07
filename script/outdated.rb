#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Fails when `bundle outdated` reports a gem of Gemfile.lock (every group, the optional ones included) that is
# not on the documented hold list (script/outdated_holds.yml), or when a listed hold is no longer outdated.

require 'open3'
require 'sorbet-runtime'
require 'yaml'

root = File.expand_path('..', __dir__)
holds = T.let(
  YAML.safe_load_file(File.join(root, 'script', 'outdated_holds.yml')),
  T::Hash[String, T::Hash[String, Object]]
)

# CI installs the bundle in deployment mode, in which `bundle outdated` refuses to run.
unfrozen = %w[env BUNDLE_DEPLOYMENT=false BUNDLE_FROZEN=false]
output, status = Open3.capture2e(*unfrozen, 'bundle', 'outdated', '--parseable', chdir: root)
# `bundle outdated` exits with 1 when it finds outdated gems; any other failure means it could not check them.
abort("bundle outdated failed (#{status}):\n#{output}") unless status.success? || status.exitstatus == 1
pattern = /^(\S+) \(newest ([^,\s]+), installed ([^,)\s]+)/
outdated = output.scan(pattern).to_h { |name, newest, installed| [name.to_s, [newest.to_s, installed.to_s]] }

unexpected = outdated.reject { |name, (newest, _)| holds.dig(name, 'newest') == newest }
stale = holds.keys - outdated.keys

outdated.each do |name, (newest, installed)|
  puts "outdated: #{name} #{installed} -> #{newest}#{' (on hold)' if holds.key?(name)}"
end
unexpected.each { |name, (newest, installed)| warn "NOT ON THE HOLD LIST: #{name} #{installed} -> #{newest}" }
stale.each { |name| warn "STALE HOLD (no longer outdated): #{name}" }
exit(unexpected.empty? && stale.empty? ? 0 : 1)
