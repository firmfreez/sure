# CI-only rehearsal: never loads Rails, dotenv, or application database settings.
require "active_record"
require "active_support/all"
require "json"
require "tempfile"
require "uri"

url = URI.parse(ENV.fetch("DATABASE_URL"))
abort "Requires the disposable HA CI database" unless ENV["CI"] == "true" &&
  %w[localhost 127.0.0.1].include?(url.host) && url.path == "/ha_upgrade_ci"

# Frozen schema and versions from fork 69b36c719078e52af818a5cd4afbdea47a3160b8.
ActiveRecord::Base.establish_connection(ENV.fetch("DATABASE_URL"))
connection = ActiveRecord::Base.connection
abort "Rehearsal requires an empty database" unless connection.tables.empty?
load File.expand_path("../test/fixtures/ha_upgrade/schema.rb.txt", __dir__)

# Schema loading uses a maximum version; restore the exact historical set so
# newly introduced backdated migrations are also exercised.
connection.execute("DELETE FROM schema_migrations")
JSON.parse(File.read(File.expand_path("../test/fixtures/ha_upgrade/versions.json", __dir__))).each do |version|
  connection.execute("INSERT INTO schema_migrations (version) VALUES (#{connection.quote(version)})")
end

family = connection.select_value("INSERT INTO families (name, created_at, updated_at) VALUES ('Synthetic HA', NOW(), NOW()) RETURNING id")
parents = %w[Food Income].map do |name|
  connection.select_value("INSERT INTO categories (family_id, name, created_at, updated_at) VALUES (#{connection.quote(family)}, #{connection.quote(name)}, NOW(), NOW()) RETURNING id")
end
parents.each do |parent|
  connection.execute("INSERT INTO categories (family_id, parent_id, name, created_at, updated_at) VALUES (#{connection.quote(family)}, #{connection.quote(parent)}, 'Shared child', NOW(), NOW())")
end

snapshot = -> do
  connection.tables.sort.to_h do |table|
    rows = connection.select_values("SELECT row_to_json(t)::text FROM #{connection.quote_table_name(table)} t")
    [ table, rows.map { |row| JSON.parse(row) } ]
  end
end
before = snapshot.call
ActiveRecord::MigrationContext.new("db/migrate").migrate
abort "Pending migrations remain" if ActiveRecord::MigrationContext.new("db/migrate").needs_migration?
Tempfile.create("ha-before") do |original|
  Tempfile.create("ha-after") do |updated|
    original.write(JSON.generate(before))
    updated.write(JSON.generate(snapshot.call))
    original.flush
    updated.flush
    system(RbConfig.ruby, "script/ha_upgrade_audit.rb", "compare", original.path, updated.path, exception: true)
  end
end
