# typed: false
# frozen_string_literal: true

# Helpers that read and write raw column values behind the gem's back, so examples
# can assert on the exact integer bitmask stored in the database.
module DatabaseHelpers
  PROTECTED_TABLES = %w[schema_migrations ar_internal_metadata].freeze
  public_constant :PROTECTED_TABLES

  # Removes every row from every test table.
  # @return [void]
  def self.truncate_all
    connection = ActiveRecord::Base.connection
    (connection.tables - PROTECTED_TABLES).each do |table|
      connection.execute("DELETE FROM #{connection.quote_table_name(table)}")
    end
  end

  # Reads the integer stored in +column+ straight from the database.
  # @param record [ActiveRecord::Base] a persisted record
  # @param column [Symbol] the column to read
  # @return [Integer, nil] the stored bitmask, or nil for SQL NULL
  def raw_value(record, column = :roles)
    value = select_raw(record, column)
    value.nil? ? nil : Integer(value)
  end

  # Overwrites +column+ in the database (bypassing the gem) and reloads +record+.
  # @param record [ActiveRecord::Base] a persisted record
  # @param value [Integer, nil] the bitmask to store, nil for SQL NULL
  # @param column [Symbol] the column to overwrite
  # @return [ActiveRecord::Base] the reloaded record
  def plant_raw_value(record, value, column = :roles)
    connection = record.class.connection
    sql_value = value.nil? ? 'NULL' : Integer(value).to_s
    connection.execute("UPDATE #{connection.quote_table_name(record.class.table_name)} " \
                       "SET #{connection.quote_column_name(column)} = #{sql_value} WHERE id = #{Integer(record.id)}")
    record.reload
  end

  # Whether the examples run against MySQL (or a compatible server such as MariaDB).
  # @return [Boolean]
  def mysql_adapter?
    ActiveRecord::Base.connection.adapter_name.match?(/mysql|trilogy|maria/i)
  end

  # Makes SQL comparable across adapters: ActiveRecord's MySQL adapter quotes every bound
  # number as a string (+& '5' > 0+), the other adapters leave it bare (+& 5 > 0+). The gem
  # binds plain Integers through ActiveRecord in both cases, so the quotes carry no meaning.
  # @param sql [String, Array<String>] a statement or statements
  # @return [String, Array<String>] the same with quoted integer literals unquoted
  def normalized_sql(sql)
    return sql.map { |statement| normalized_sql(statement) } if sql.is_a?(Array)

    sql.gsub(/'(-?\d+)'/, '\1')
  end

  # The fully qualified, adapter-quoted column reference used in generated SQL.
  # @param model [Class] an ActiveRecord model
  # @param column [Symbol] the column name
  # @return [String] for example "users"."roles" (quoting depends on the adapter)
  def qualified_column(model, column = :roles)
    "#{model.connection.quote_table_name(model.table_name)}.#{model.connection.quote_column_name(column)}"
  end

  private

  # Selects the raw column value for +record+.
  # @param record [ActiveRecord::Base]
  # @param column [Symbol]
  # @return [Object]
  def select_raw(record, column)
    connection = record.class.connection
    table = connection.quote_table_name(record.class.table_name)
    connection.select_value("SELECT #{connection.quote_column_name(column)} FROM #{table} " \
                            "WHERE id = #{Integer(record.id)}")
  end
end
