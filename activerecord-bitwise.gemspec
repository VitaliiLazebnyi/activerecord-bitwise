# frozen_string_literal: true

require_relative 'lib/active_record/bitwise/version'

Gem::Specification.new do |spec|
  spec.name          = 'activerecord-bitwise'
  spec.version       = ActiveRecord::Bitwise::VERSION
  spec.authors       = ['VitaliiLazebnyi']
  spec.email         = ['vitalii.lazebnyi.github@gmail.com']

  spec.summary       = 'Store multiple boolean values as a single integer bitmask.'
  spec.description   = 'A Ruby gem that extends ActiveRecord to support bitwise enum mapping, ' \
                       'allowing multiple states to be saved in a single database column.'
  spec.homepage      = 'https://github.com/VitaliiLazebnyi/activerecord-bitwise'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.3.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['source_code_uri']   = spec.homepage
  spec.metadata['changelog_uri']     = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Code signing configuration
  cert_path = File.expand_path('certs/activerecord-bitwise-public_cert.pem', __dir__)
  if File.exist?(cert_path)
    spec.cert_chain = [cert_path]
    private_key_path = File.expand_path('~/.gem/gem-private_key.pem')
    # Ensure the key file actually has substantial content (not just a newline from an empty secret)
    spec.signing_key = private_key_path if File.exist?(private_key_path) && File.size(private_key_path) > 100
  end

  # Use native globbing to avoid git requirement.
  # Internal development documents (BUGS.md, REQUIREMENTS.md) are intentionally
  # NOT shipped in the packaged gem.
  spec.files         = Dir.glob('{lib,certs}/**/*') + %w[README.md LICENSE.txt CHANGELOG.md]
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # ActiveRecord 7.1 is the oldest release the gem actually loads and passes its
  # suite against (older releases fail to resolve alongside the required Ruby
  # 3.3+ / sqlite3 2.x toolchain). The < 9 ceiling exists because the gem
  # patches ActiveRecord internals (Relation#update_all/#where) and must be
  # re-verified per major release.
  spec.add_dependency 'activerecord', '>= 7.1', '< 9'
  spec.add_dependency 'sorbet-runtime', '~> 0.6'

  # Test suite.
  spec.add_development_dependency 'rspec', '~> 3.13'
  spec.add_development_dependency 'simplecov', '~> 1.3'
  spec.add_development_dependency 'simplecov-ai', '~> 0.11'
  spec.add_development_dependency 'sqlite3', '~> 2.10'

  # Quality tooling (linting, typing, documentation, mutation testing, dependency audit).
  # Fails the build on dependencies with known vulnerabilities.
  spec.add_development_dependency 'bundler-audit', '~> 0.9'
  # Structural duplication detection.
  spec.add_development_dependency 'flay', '~> 2.14'
  # Mutation testing (free for open source via `usage: opensource`).
  spec.add_development_dependency 'mutant-rspec', '~> 0.17'
  # Code smell detection.
  spec.add_development_dependency 'reek', '~> 6.6'
  # Rake tasks.
  spec.add_development_dependency 'rake', '~> 13.4'
  # Linter and its plugins.
  spec.add_development_dependency 'rubocop', '~> 1.92'
  spec.add_development_dependency 'rubocop-md', '~> 2.0'
  spec.add_development_dependency 'rubocop-performance', '~> 1.27'
  spec.add_development_dependency 'rubocop-rake', '~> 0.7'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.10'
  spec.add_development_dependency 'rubocop-sorbet', '~> 0.17'
  spec.add_development_dependency 'rubocop-thread_safety', '~> 0.8'
  # Static type checker.
  spec.add_development_dependency 'sorbet', '~> 0.6'
  # API documentation (must stay 100% documented) and its Sorbet plugin.
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'yard-sorbet', '~> 0.9'
end
