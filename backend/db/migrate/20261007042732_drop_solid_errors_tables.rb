class DropSolidErrorsTables < ActiveRecord::Migration[8.1]
  TABLES = [
    :solid_errors_occurrences,
    :solid_errors,
  ]

  def up
    TABLES.each do |table|
      drop_table table, if_exists: true
    end
  end

  def down = nil
end
