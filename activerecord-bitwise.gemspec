# frozen_string_literal: true

require_relative 'lib/active_record/bitwise/version'

Gem::Specification.new do |spec|
  spec.name          = 'activerecord-bitwise'
  spec.version       = ActiveRecord::Bitwise::VERSION
  spec.authors       = ['VitaliiLazebnyi']
  spec.email         = ['vitalii.lazebnyi.github@gmail.com']

  spec.summary       = 'Store multiple boolean values as a single integer bitmask.'
  spec.description   = 'A Ruby gem that extends ActiveRecord to support bitwise enum mapping, allowing multiple states to be saved in a single database column.'
  spec.homepage      = 'https://github.com/VitaliiLazebnyi/activerecord-bitwise'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

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

  # Use native globbing to avoid git requirement
  spec.files         = Dir.glob('{lib,certs}/**/*') + %w[README.md LICENSE.txt CHANGELOG.md BUGS.md REQUIREMENTS.md]
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Enforce targeted active record combinations
  spec.add_dependency 'activerecord', '>= 5.0'
  spec.add_dependency 'sorbet-runtime', '~> 0.6'

  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.50'
  spec.add_development_dependency 'rubocop-md', '~> 1.2'
  spec.add_development_dependency 'rubocop-performance', '~> 1.21'
  spec.add_development_dependency 'rubocop-rspec', '~> 3.0'
  spec.add_development_dependency 'rubocop-thread_safety', '~> 0.6'
  spec.add_development_dependency 'simplecov', '~> 0.22'
  spec.add_development_dependency 'simplecov-ai', '~> 0.10'
  spec.add_development_dependency 'sorbet', '~> 0.5'
  spec.add_development_dependency 'sqlite3', '~> 2.1'
  spec.add_development_dependency 'yard', '~> 0.9'
  spec.add_development_dependency 'yard-sorbet', '~> 0.6'
end
