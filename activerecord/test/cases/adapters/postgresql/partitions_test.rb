# frozen_string_literal: true

require "cases/helper"

class PostgreSQLPartitionsTest < ActiveRecord::PostgreSQLTestCase
  self.use_transactional_tests = false

  def setup
    @previous_unlogged_tables = ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.create_unlogged_tables
    @connection = ActiveRecord::Base.lease_connection
    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.create_unlogged_tables = false
  end

  def teardown
    @connection.remove_index "partitioned_events", name: "index_partitioned_events_on_issued_at", if_exists: true, algorithm: :concurrently
    @connection.drop_table "partitioned_events", if_exists: true
    @connection.drop_table "partitioned_events_2024", if_exists: true
    @connection.drop_table "partitioned_events_2025", if_exists: true
    ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.create_unlogged_tables = @previous_unlogged_tables
  end

  def test_partitions_table_exists
    skip unless ActiveRecord::Base.lease_connection.database_version >= 100000
    @connection.create_table :partitioned_events, force: true, id: false,
      options: "partition by range (issued_at)" do |t|
      t.timestamp :issued_at
    end
    assert @connection.table_exists?("partitioned_events")
  end

  def test_add_index_builds_partitioned_index
    skip unless ActiveRecord::Base.lease_connection.database_version >= 110000

    @connection.create_table :partitioned_events, force: true, id: false,
      options: "partition by range (issued_at)" do |t|
      t.timestamp :issued_at
    end

    @connection.create_table :partitioned_events_2024, id: false,
      options: "PARTITION OF partitioned_events FOR VALUES FROM ('2024-01-01') TO ('2025-01-01')"
    @connection.create_table :partitioned_events_2025, id: false,
      options: "PARTITION OF partitioned_events FOR VALUES FROM ('2025-01-01') TO ('2026-01-01')"

    @connection.add_index :partitioned_events, :issued_at, algorithm: :concurrently

    index_names = @connection.indexes("partitioned_events").map(&:name)
    assert_includes index_names, "index_partitioned_events_on_issued_at"

    @connection.remove_index :partitioned_events, name: "index_partitioned_events_on_issued_at", algorithm: :concurrently
    index_names = @connection.indexes("partitioned_events").map(&:name)
    assert_not_includes index_names, "index_partitioned_events_on_issued_at"
  end
end
