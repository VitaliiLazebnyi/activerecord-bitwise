# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Helpers that read and write raw column values behind the gem's back, so examples
# can assert on the exact integer bitmask stored in the database.
module DatabaseHelpers
  extend T::Sig

  PROTECTED_TABLES = %w[schema_migrations ar_internal_metadata].freeze
  public_constant :PROTECTED_TABLES

  module_function

  # Removes every row from every test table.
  # @return [void]
  sig { void }
  def truncate_all
    connection = ActiveRecord::Base.connection
    (connection.tables - PROTECTED_TABLES).each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
    end
  end

  # Reads the integer stored in +column+ straight from the database.
  # @param record [ActiveRecord::Base] a persisted record
  # @param column [Symbol] the column to read
  # @return [Integer, nil] the stored bitmask, or nil for SQL NULL
  sig { params(record: ActiveRecord::Base, column: Symbol).returns(T.nilable(Integer)) }
  def raw_value(record, column = :roles)
    RawColumn.new(record, column).read
  end

  # Overwrites +column+ in the database (bypassing the gem) and reloads +record+.
  # @param record [ActiveRecord::Base] a persisted record
  # @param value [Integer, nil] the bitmask to store, nil for SQL NULL
  # @param column [Symbol] the column to overwrite
  # @return [ActiveRecord::Base] the reloaded record
  # @raise [ArgumentError] if +record+ is not an ActiveRecord model instance
  sig do
    type_parameters(:Record)
      .params(record: T.type_parameter(:Record), value: T.nilable(Integer), column: Symbol)
      .returns(T.type_parameter(:Record))
  end
  def plant_raw_value(record, value, column = :roles)
    case record
    when ActiveRecord::Base
      RawColumn.new(record, column).write(value)
      record.reload
    else
      Kernel.raise(ArgumentError, 'plant_raw_value needs an ActiveRecord model instance')
    end
    record
  end

  # The byte limit the connected database reports for a column.
  # @param table [String]
  # @param column [String]
  # @return [Integer, nil]
  sig { params(table: String, column: String).returns(T.nilable(Integer)) }
  def column_limit(table, column)
    ActiveRecord::Base.connection.columns(table).find { |candidate| candidate.name == column }
      &.limit
  end

  # Whether the examples run against PostgreSQL.
  # @return [Boolean]
  sig { returns(T::Boolean) }
  def postgres_adapter?
    ActiveRecord::Base.connection.adapter_name.match?(/postg/i)
  end

  # Makes SQL comparable across adapters: ActiveRecord's MySQL adapter quotes every bound
  # number as a string (+& '5' > 0+), the other adapters leave it bare (+& 5 > 0+). The gem
  # binds plain Integers through ActiveRecord in both cases, so the quotes carry no meaning.
  # @param sql [String] a statement
  # @return [String] the same with quoted integer literals unquoted
  sig { params(sql: String).returns(String) }
  def normalized_sql(sql)
    sql.gsub(/'(-?\d+)'/, '\1')
  end

  # {normalized_sql} of every statement.
  # @param statements [Array<String>]
  # @return [Array<String>]
  sig { params(statements: T::Array[String]).returns(T::Array[String]) }
  def normalized_statements(statements)
    statements.map { |statement| normalized_sql(statement) }
  end

  # The fully qualified, adapter-quoted column reference used in generated SQL.
  # @param model [Class] an ActiveRecord model
  # @param column [Symbol] the column name
  # @return [String] for example "users"."roles" (quoting depends on the adapter)
  sig { params(model: T.class_of(ActiveRecord::Base), column: Symbol).returns(String) }
  def qualified_column(model, column = :roles)
    connection = model.connection
    "#{connection.quote_table_name(model.table_name)}.#{connection.quote_column_name(column)}"
  end

  # One column of one persisted record, read and written with plain SQL.
  class RawColumn
    extend T::Sig

    # @param record [ActiveRecord::Base] a persisted record
    # @param column [Symbol] the column
    sig { params(record: ActiveRecord::Base, column: Symbol).void }
    def initialize(record, column)
      model = record.class
      @connection = T.let(model.connection, ActiveRecord::ConnectionAdapters::AbstractAdapter)
      @column = T.let(@connection.quote_column_name(column), String)
      @table = T.let(model.quoted_table_name, String)
      @id = T.let(Integer(record.id), Integer)
    end

    # The value stored in the column.
    # @return [Integer, nil] nil for SQL NULL
    sig { returns(T.nilable(Integer)) }
    def read
      value = @connection.select_value("SELECT #{@column} FROM #{@table} WHERE id = #{@id}")
      Integer(value, exception: false)
    end

    # Stores +value+ in the column.
    # @param value [Integer, nil] nil for SQL NULL
    # @return [void]
    sig { params(value: T.nilable(Integer)).void }
    def write(value)
      @connection.execute("UPDATE #{@table} SET #{@column} = #{@connection.quote(value)} WHERE id = #{@id}")
    end
  end
end
