# Capture: bin/rails runner script/ha_upgrade_audit.rb capture /private/path/before.json
# Compare (no database access): ruby script/ha_upgrade_audit.rb compare before.json after.json
require "json"

mode, first, second = ARGV
abort "Usage: capture FILE (rails runner) | compare BEFORE AFTER" unless first && %w[capture compare].include?(mode)

if mode == "capture"
  abort "Use bin/rails runner for capture" unless defined?(ActiveRecord::Base)
  snapshot = ActiveRecord::Base.transaction do
    connection = ActiveRecord::Base.connection
    connection.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ, READ ONLY")
    connection.tables.sort.to_h do |table|
      rows = connection.select_values("SELECT row_to_json(t)::text FROM #{connection.quote_table_name(table)} t")
      [ table, rows.map { |row| JSON.parse(row) } ]
    end
  end
  File.open(first, File::WRONLY | File::CREAT | File::EXCL, 0o600) { |file| file.write(JSON.generate(snapshot)) }
  puts "Captured #{snapshot.size} tables. Keep this private: it contains financial and authentication data."
else
  abort "An AFTER snapshot is required" unless second
  before = JSON.parse(File.read(first))
  after = JSON.parse(File.read(second))
  failures = []
  before.each do |table, rows|
    next if table == "ar_internal_metadata" # Rails records schema/environment bookkeeping here.

    current = after.fetch(table, [])
    if rows.first&.key?("id")
      by_id = current.to_h { |row| [ row.fetch("id"), row ] }
      missing = rows.count { |row| !by_id.key?(row.fetch("id")) }
      changed = Hash.new(0)
      rows.each do |row|
        updated = by_id[row.fetch("id")]
        next unless updated

        row.each do |column, value|
          target_column = table == "categories" && column == "classification" ? "classification_unused" : column
          actual = updated[target_column]
          expected = table == "addresses" && column == "postal_code" && !value.nil? ? value.to_s : value
          changed[column] += 1 unless updated.key?(target_column) && actual == expected
        end
      end
      failures << "#{table}: #{missing} missing IDs, changed columns #{changed}" if missing.positive? || changed.any?
      puts "#{table}: #{rows.size} -> #{current.size}, missing IDs: #{missing}, changed original fields: #{changed.values.sum}"
    elsif (rows - current).any?
      failures << "#{table}: original rows missing"
    end
  end
  abort failures.join("\n") if failures.any?
  puts "PASS: every original record and field preserved (including documented lossless column conversions)."
end
