# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

source 'https://rubygems.org'

# The gem with its runtime and development dependencies (activerecord-bitwise.gemspec). Gemfile.lock pins
# them for every single-version check; the test matrix resolves its own bundles from gemfiles/.
gemspec

# `rake typecheck` only (BUNDLE_WITH=typecheck). The group is optional so that the specs run without Tapioca:
# loading it changes how lib/tapioca/dsl/compilers/activerecord_bitwise.rb is loaded, and the specs exercise
# its stand-in for Tapioca's compiler base class.
group :typecheck, optional: true do
  # Generates the RBI files of the bundled gems that Sorbet checks against.
  gem 'tapioca', '~> 0.20', require: false
end
