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

  # Instances report their model class, which carries the macros above.
  sig { returns(T.class_of(ActiveRecord::Base)) }
  def class; end
end

# Bundler vendors connection_pool as Bundler::ConnectionPool, whose fork tracker extends Process while Tapioca
# runs; the generated RBI of sqlite3 (which also extends Process) records that mixin, so Sorbet must know it.
class Bundler::ConnectionPool; end
module Bundler::ConnectionPool::ForkTracker; end
