# typed: strict

# What the gem adds to ActiveRecord::Base when ActiveSupport loads it (see lib/active_record/bitwise.rb).
class ActiveRecord::Base
  extend ActiveRecord::Bitwise::Model

  # The bitwise columns declared on the class, defined with +class_attribute+ by Model.extended.
  sig { returns(T::Hash[Symbol, ActiveRecord::Bitwise::Declaration::Definition]) }
  def self.bitwise_definitions; end

  sig do
    params(value: T::Hash[Symbol, ActiveRecord::Bitwise::Declaration::Definition])
      .returns(T::Hash[Symbol, ActiveRecord::Bitwise::Declaration::Definition])
  end
  def self.bitwise_definitions=(value); end

  # The instance reader that +class_attribute+ defines next to the class-level one.
  sig { returns(T::Hash[Symbol, ActiveRecord::Bitwise::Declaration::Definition]) }
  def bitwise_definitions; end

  # Instances report their model class, which carries the macros above.
  sig { returns(T.class_of(ActiveRecord::Base)) }
  def class; end
end

# Bundler vendors connection_pool as Bundler::ConnectionPool, whose fork tracker extends Process while Tapioca
# runs; the generated RBI of sqlite3 (which also extends Process) records that mixin, so Sorbet must know it.
class Bundler::ConnectionPool; end
module Bundler::ConnectionPool::ForkTracker; end

# RSpec mixes its mock and matcher DSLs, and the suite's own helpers, into every example group at runtime
# (`config.mock_with`, `config.expect_with` and `config.include` in spec/spec_helper.rb); Sorbet's RSpec support
# (`--enable-experimental-rspec`, sorbet/config) needs the same ancestry declared. RSpec::Matchers comes after
# the mocks so that its `expect`, which also takes a block, wins over the value-only `expect` of
# RSpec::Mocks::ExampleMethods::ExpectHost, as it does at runtime.
class RSpec::Core::ExampleGroup
  include ::RSpec::Mocks::ExampleMethods
  include ::RSpec::Matchers
  include ::DatabaseHelpers
  include ::ModelFactory
  include ::RawMarker
  include ::ErrorCapture
  include ::SqlCapture
  include ::RowLockSpy
  include ::ConcurrentRunner
end

# RSpec answers every `be_<predicate>` matcher through method_missing (RSpec::Matchers#method_missing); these
# are the predicate matchers the suite uses.
module RSpec::Matchers
  sig { returns(RSpec::Matchers::BuiltIn::BePredicate) }
  def be_empty; end

  sig { returns(RSpec::Matchers::BuiltIn::BePredicate) }
  def be_frozen; end

  sig { returns(RSpec::Matchers::BuiltIn::BePredicate) }
  def be_new_record; end

  sig { returns(RSpec::Matchers::BuiltIn::BePredicate) }
  def be_persisted; end

  sig { returns(RSpec::Matchers::BuiltIn::BePredicate) }
  def be_success; end

  sig { returns(RSpec::Matchers::BuiltIn::BePredicate) }
  def be_valid; end
end

# Sorbet's RBI of the core library declares no constructor for Fiber, which takes the block the fiber runs.
class Fiber
  sig do
    params(
      blocking: T::Boolean,
      storage: T.nilable(T::Hash[Symbol, T.anything]),
      blk: T.proc.params(args: T.anything).returns(T.anything)
    ).void
  end
  def initialize(blocking: false, storage: nil, &blk); end
end
