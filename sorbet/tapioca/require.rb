# typed: true
# frozen_string_literal: true

# Loading ActiveSupport::Configurable prints a deprecation notice (Rails 8.1 deprecates it without
# replacement), and Tapioca loads every constant it finds while it compiles the RBIs. Neither this gem nor
# any of its dependencies uses that module, so its autoload is removed (without loading it) before the
# RBIs are compiled.
ActiveSupport.__send__(:remove_const, :Configurable) if ActiveSupport.autoload?(:Configurable)
