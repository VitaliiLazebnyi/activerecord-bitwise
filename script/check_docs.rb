#!/usr/bin/env ruby
# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Fails unless every object of the YARD registry (.yardoc, written by `yardoc`) has a written description.
# `yard stats` alone is not enough: yard-sorbet derives @param and @return tags from each `sig`, and YARD
# counts an object with tags as documented, so a method without any comment would still pass it.

require 'sorbet-runtime'
require 'yard'

YARD::Registry.load!(File.expand_path('../.yardoc', __dir__))
undescribed = YARD::Registry.all.select { |object| object.docstring.strip.empty? }
undescribed.each { |object| warn "No description: #{object.path} (#{object.file}:#{object.line})" }
puts "#{YARD::Registry.all.size} objects, #{undescribed.size} without a description"
exit(undescribed.empty? ? 0 : 1)
