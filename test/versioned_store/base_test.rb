# frozen_string_literal: true

require "test_helper"

module VersionedStore
  class BaseTest < Minitest::Test
    def test_create_read_update_destroy
      tmpdir = Dir.mktmpdir

      test_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:record_1s) do |t|
            t.string(:attr_1)
            t.string(:attr_2)
          end
        end

        record(:record_1, table: :record_1s) do
          def something?
            attr_1 == "attr_1_1"
          end
        end
      end

      store = test_store_class.new(dir: tmpdir)


      record = store.record_1.transaction do
        store.record_1.create!(
          attr_1: "attr_1_1",
          attr_2: "attr_2_1"
        )
      end

      assert_equal 1, store.record_1.count
      assert_equal "attr_1_1", record.attr_1
      assert_equal "attr_2_1", record.attr_2
      assert record.something?

      store.record_1.transaction do
        record.update!(attr_1: "attr_1_updated")
      end

      assert_equal "attr_1_updated", record.attr_1
      assert_equal "attr_2_1", record.attr_2

      reloaded = store.record_1.find(record.id)
      assert_equal "attr_1_updated", reloaded.attr_1
      assert_equal "attr_2_1", reloaded.attr_2

      assert_equal 2, store.versions.length

      # can seamlessly browse other versions
      original_record = store.versions[0].record_1.find(record.id)
      assert_equal "attr_1_1", original_record.attr_1
      assert_equal "attr_2_1", original_record.attr_2

      updated_record = store.versions[1].record_1.find(record.id)
      assert_equal "attr_1_updated", updated_record.attr_1
      assert_equal "attr_2_1", updated_record.attr_2
    end

    def test_can_recover_existing_dir
      tmpdir = Dir.mktmpdir

      # First, create a database with some data
      initial_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:record_1s) do |t|
            t.string(:attr_1)
            t.string(:attr_2)
          end
        end

        record(:record_1, table: :record_1s)
      end

      initial_store = initial_store_class.new(dir: tmpdir)

      record = initial_store.record_1.create!(
        attr_1: "attr_1_1",
        attr_2: "attr_2_1"
      )

      # Now create a new store instance pointing to the same directory
      recovery_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:record_1s) do |t|
            t.string(:attr_1)
            t.string(:attr_2)
          end
        end

        record(:record_1, table: :record_1s)
      end

      store = recovery_store_class.new(dir: tmpdir)

      assert_equal 1, store.record_1.count

      reloaded_record = store.record_1.find(record.id)
      assert_equal "attr_1_1", record.attr_1
      assert_equal "attr_2_1", record.attr_2
    end

    def test_attribute_defaults
      tmpdir = Dir.mktmpdir

      defaults_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:record_1s) do |t|
            t.string(:status, default: "pending")
            t.integer(:count, default: 0)
            t.boolean(:boolean, default: false)
            t.string(:name)
          end
        end

        record(:record_1, table: :record_1s)
      end

      store = defaults_store_class.new(dir: tmpdir)

      # Create record without specifying default attributes
      record = store.record_1.create!(name: "Test")
      assert_equal "pending", record.status  # Should have default value
      assert_equal false, record.boolean  # Should have default value
      assert_equal 0, record.count          # Should have default value
      assert_equal "Test", record.name

      # Create record with explicit values overriding defaults
      record2 = store.record_1.create!(status: "active", count: 5, name: "Test2")
      assert_equal "active", record2.status  # Should use provided value
      assert_equal 5, record2.count         # Should use provided value
      assert_equal "Test2", record2.name
    end

    def test_update_with_invalid_attribute_raises_error
      tmpdir = Dir.mktmpdir

      invalid_attribute_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:record_1s) do |t|
            t.string(:name)
          end
        end

        record(:record_1, table: :record_1s)
      end

      store = invalid_attribute_store_class.new(dir: tmpdir)

      record = store.record_1.create!(name: "Original")

      error = assert_raises(ActiveRecord::UnknownAttributeError) do
        record.update!(invalid_attribute: "value")
      end

      assert_match(/invalid_attribute/, error.message)
    end

    def test_update_uses_setter_methods
      tmpdir = Dir.mktmpdir

      setter_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:record_1s) do |t|
            t.string(:name)
          end
        end

        record(:record_1, table: :record_1s) do
          def name=(value)
            super(value.upcase)
          end
        end
      end

      store = setter_store_class.new(dir: tmpdir)

      record = store.record_1.create!(name: "original")

      record.update!(name: "updated")

      reloaded = store.record_1.find(record.id)
      assert_equal "UPDATED", reloaded.name
    end

    def test_transaction
      tmpdir = Dir.mktmpdir

      transaction_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:attr)
          end
        end

        record(:record, table: :records)
      end

      store = transaction_store_class.new(dir: tmpdir)

      store.record.transaction { store.record.create!(attr: "attr") }
      store.record.transaction { store.record.create!(attr: "attr") }

      record_1, record_2 = store.record.all.to_a

      assert_equal 2, store.versions.count

      store.transaction do
        record_1.update!(attr: "attr_updated")
        record_2.update!(attr: "attr_updated")
      end

      assert_equal 3, store.versions.count
    end

    def test_transaction_rollback_on_error
      tmpdir = Dir.mktmpdir

      rollback_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:attr)
          end
        end

        record(:record, table: :records)
      end

      store = rollback_store_class.new(dir: tmpdir)

      store.record.transaction { store.record.create!(attr: "original") }
      assert_equal 1, store.versions.count

      begin
        store.transaction do
          record = store.record.first
          record.update!(attr: "updated")
          raise "Something went wrong"
        end
      rescue => e
        # Exception expected
      end

      # Version count should not change due to rollback
      assert_equal 1, store.versions.count

      # Record should still have original value
      record = store.record.first
      assert_equal "original", record.attr
    end

    def test_restore
      tmpdir = Dir.mktmpdir

      restore_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:value)
          end
        end

        record(:record, table: :records)
      end

      store = restore_store_class.new(dir: tmpdir)

      # Create initial versions
      record_1 = store.record.transaction { store.record.create!(value: "v1") }
      record_2 = store.record.transaction { store.record.create!(value: "v2") }
      store.record.transaction { record_1.update!(value: "v1_updated") }

      # Should have 3 versions now
      assert_equal 3, store.versions.count

      # Verify current data has the updated value
      latest_record = store.record.find(record_1.id)
      assert_equal "v1_updated", latest_record.value

      # Restore to version 1 (first create)
      restored_store = store.versions[0].restore

      # Should only have 2 versions after restore
      assert_equal 2, restored_store.versions.count

      # Verify we can read the correct data
      records = restored_store.record.all.to_a
      assert_equal 1, records.count
      assert_equal record_1.id, records[0].id
      assert_equal "v1", records[0].value

      # Verify we can continue working after restore
      record_3 = restored_store.record.transaction { restored_store.record.create!(value: "v3") }
      assert_equal 3, restored_store.versions.count

      # Verify data has both records
      latest_records = restored_store.record.all.to_a
      assert_equal 2, latest_records.count

      reloaded_1 = latest_records.find { |r| r.id == record_1.id }
      reloaded_3 = latest_records.find { |r| r.id == record_3.id }

      assert_equal "v1", reloaded_1.value
      assert_equal "v3", reloaded_3.value
    end

    def test_schema_inside_record_block
      tmpdir = Dir.mktmpdir

      schema_store_class = Class.new(VersionedStore::Base) do
        # Define a record with schema inline
        record(:my_record) do
          schema(:my_records) do |t|
            t.string(:name)
            t.integer(:value)
          end

          def custom_method
            "#{name}: #{value}"
          end
        end

        # Add another regular migration that should come after the schema
        migrate do
          create_table(:other_table) do |t|
            t.string(:data)
          end
        end
      end

      store = schema_store_class.new(dir: tmpdir)

      # Verify the schema migration was created and placed first
      assert_equal 2, store.schema.migrations.count

      # First migration should be the schema with table name as version (now a string)
      first_migration = store.schema.migrations[0]
      assert_equal "table_my_records", first_migration.version

      # Second migration should be the regular migrate (version 2)
      second_migration = store.schema.migrations[1]
      assert_equal 2, second_migration.version

      # Verify the table was created and we can use it
      record = store.my_record.create!(name: "Test", value: 42)
      assert_equal "Test", record.name
      assert_equal 42, record.value
      assert_equal "Test: 42", record.custom_method

      # Verify we can query the record
      reloaded = store.my_record.find(record.id)
      assert_equal "Test", reloaded.name
      assert_equal 42, reloaded.value

      # Verify other_table was also created
      assert store.schema.records.key?(:my_record)
    end

    def test_belongs_to_and_has_many_relationships
      tmpdir = Dir.mktmpdir

      relationship_store_class = Class.new(VersionedStore::Base) do
        # Create parent record (author)
        record(:author) do
          schema(:authors) do |t|
            t.string(:name)
          end

          has_many(
            :posts,
            foreign_key: :author_id,
            class_name: class_name(:post),
            inverse_of: :author
          )
        end

        # Create child record (post)
        record(:post) do
          schema(:posts) do |t|
            t.string(:title)
            t.text(:content)
            t.integer(:author_id)
          end

          belongs_to(
            :author,
            class_name: class_name(:author),
            inverse_of: :posts
          )
        end
      end

      store = relationship_store_class.new(dir: tmpdir)

      # Create an author
      author = store.author.transaction do
        store.author.create!(name: "Jane Doe")
      end

      assert_equal "Jane Doe", author.name
      assert_equal 1, store.author.count

      # Create posts associated with the author
      post1 = store.post.transaction do
        store.post.create!(
          title: "First Post",
          content: "This is the first post",
          author_id: author.id
        )
      end

      post2 = store.post.transaction do
        store.post.create!(
          title: "Second Post",
          content: "This is the second post",
          author_id: author.id
        )
      end

      assert_equal 2, store.post.count
      assert_equal "First Post", post1.title
      assert_equal author.id, post1.author_id

      # Test belongs_to relationship
      reloaded_post1 = store.post.find(post1.id)
      assert_equal author.id, reloaded_post1.author.id
      assert_equal "Jane Doe", reloaded_post1.author.name

      # Test has_many relationship
      reloaded_author = store.author.find(author.id)
      author_posts = reloaded_author.posts.to_a
      assert_equal 2, author_posts.count
      assert_equal author.object_id, author.posts.first.author.object_id
      assert_equal ["First Post", "Second Post"], author_posts.map(&:title).sort

      # Test relationships on versions
      assert_equal 3, store.versions.count

      # Version 0: only author exists
      v0_author = store.versions[0].author.find(author.id)
      assert_equal "Jane Doe", v0_author.name
      assert_equal 0, v0_author.posts.count

      # Version 1: author + first post
      v1_author = store.versions[1].author.find(author.id)
      v1_posts = v1_author.posts.to_a
      assert_equal 1, v1_posts.count
      assert_equal "First Post", v1_posts.first.title

      v1_post = store.versions[1].post.find(post1.id)
      assert_equal author.id, v1_post.author.id
      assert_equal "Jane Doe", v1_post.author.name

      # Version 2: author + both posts
      v2_author = store.versions[2].author.find(author.id)
      v2_posts = v2_author.posts.to_a
      assert_equal 2, v2_posts.count
      assert_equal ["First Post", "Second Post"], v2_posts.map(&:title).sort

      v2_post1 = store.versions[2].post.find(post1.id)
      v2_post2 = store.versions[2].post.find(post2.id)
      assert_equal author.id, v2_post1.author.id
      assert_equal author.id, v2_post2.author.id
      assert_equal "Jane Doe", v2_post1.author.name
      assert_equal "Jane Doe", v2_post2.author.name
    end

    def test_record_blocks_are_additive
      tmpdir = Dir.mktmpdir

      # Clean up any previous test database files
      db_file = File.join(tmpdir, "db.sqlite3")
      File.delete(db_file) if File.exist?(db_file)
      versions_dir = File.join(tmpdir, "versions")
      if Dir.exist?(versions_dir)
        Dir.glob(File.join(versions_dir, "*.sqlite3")).each { |f| File.delete(f) }
      end

      additive_store_class = Class.new(VersionedStore::Base) do
        record(:state) do
          schema(:states) do |t|
            t.string(:name)
          end

          def hello
            "hello"
          end
        end

        record(:state) do
          schema(:states) do |t|
            t.string(:country)
          end

          def bye
            "bye"
          end
        end
      end

      store = additive_store_class.new(dir: tmpdir)

      state = store.state.create!(name: "oregon", country: "usa")

      assert_equal "hello", state.hello
      assert_equal "bye", state.bye
    end

    def test_default_table_name_adds_s
      tmpdir = Dir.mktmpdir

      default_table_store_class = Class.new(VersionedStore::Base) do
        record(:author) do
          schema do |t|
            t.string(:name)
          end
        end
      end

      store = default_table_store_class.new(dir: tmpdir)

      # Verify table names were inferred correctly
      assert_equal :authors, store.schema.records[:author].table
    end

    def test_named_snapshots
      tmpdir = Dir.mktmpdir

      snapshot_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:value)
          end
        end

        record(:record, table: :records)
      end

      store = snapshot_store_class.new(dir: tmpdir)

      # Create initial state
      record_1 = store.record.transaction { store.record.create!(value: "state_1") }

      # Create a named snapshot
      store.snapshot("checkpoint_1")

      # Make more changes
      record_2 = store.record.transaction { store.record.create!(value: "state_2") }
      store.record.transaction { record_1.update!(value: "state_1_updated") }

      # Create another named snapshot
      store.snapshot("checkpoint_2")

      # Make even more changes
      store.record.transaction { record_2.update!(value: "state_2_updated") }

      # Verify current state
      records = store.record.all.to_a.sort_by(&:id)
      assert_equal 2, records.count
      assert_equal "state_1_updated", records[0].value
      assert_equal "state_2_updated", records[1].value

      # Restore to checkpoint_1
      restored_store = store.restore("checkpoint_1")

      # Verify we're back to checkpoint_1 state
      restored_records = restored_store.record.all.to_a
      assert_equal 1, restored_records.count
      assert_equal record_1.id, restored_records[0].id
      assert_equal "state_1", restored_records[0].value

      # Verify we can continue working after restore
      record_3 = restored_store.record.transaction { restored_store.record.create!(value: "state_3") }

      final_records = restored_store.record.all.to_a.sort_by(&:id)
      assert_equal 2, final_records.count
      assert_equal "state_1", final_records[0].value
      assert_equal "state_3", final_records[1].value

      # Create a new snapshot and verify we can restore to it later
      restored_store.snapshot("checkpoint_3")
      restored_store.record.transaction { record_3.update!(value: "state_3_updated") }

      # Restore to checkpoint_3
      final_store = restored_store.restore("checkpoint_3")
      final_check = final_store.record.all.to_a.sort_by(&:id)
      assert_equal 2, final_check.count
      assert_equal "state_1", final_check[0].value
      assert_equal "state_3", final_check[1].value
    end

    def test_store_access_from_class_and_instance
      tmpdir = Dir.mktmpdir

      store_access_class = Class.new(VersionedStore::Base) do
        record(:author) do
          schema(:authors) do |t|
            t.string(:name)
          end
        end

        record(:post) do
          schema(:posts) do |t|
            t.string(:title)
            t.integer(:author_id)
          end
        end
      end

      store = store_access_class.new(dir: tmpdir)

      # Test class-level store access
      assert_equal store, store.author.store
      assert_equal store, store.post.store

      # Create an author and test instance-level store access
      author = store.author.create!(name: "John Doe")
      assert_equal store, author.store

      # Test that instance can use store to interact with other records
      post = author.store.post.create!(
        title: "My Post",
        author_id: author.id
      )

      assert_equal "My Post", post.title
      assert_equal author.id, post.author_id
      assert_equal store, post.store

      # Verify both records can access the store
      reloaded_author = store.author.find(author.id)
      reloaded_post = store.post.find(post.id)

      assert_equal store, reloaded_author.store
      assert_equal store, reloaded_post.store

      # Verify instance can query other records through store
      all_posts = reloaded_author.store.post.where(author_id: author.id).to_a
      assert_equal 1, all_posts.count
      assert_equal post.id, all_posts.first.id
    end

    def test_versioned_false_does_not_create_versions
      tmpdir = Dir.mktmpdir

      non_versioned_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:value)
          end
        end

        record(:record, table: :records)
      end

      store = non_versioned_store_class.new(dir: tmpdir, versioned: false)

      # Create records through transactions
      store.record.transaction { store.record.create!(value: "v1") }
      store.record.transaction { store.record.create!(value: "v2") }
      store.record.transaction { store.record.create!(value: "v3") }

      # Verify no versions were created
      assert_equal 0, store.versions.count

      # Verify the records were still created successfully
      assert_equal 3, store.record.count
      assert_equal ["v1", "v2", "v3"], store.record.order(:id).pluck(:value)
    end

    def test_hash_config_initialization
      tmpdir = Dir.mktmpdir

      simple_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:items) do |t|
            t.string(:name)
          end
        end

        record(:item, table: :items)
      end

      # Test with hash config
      store = simple_store_class.new( dir: tmpdir )
      assert_instance_of VersionedStore::Config, store.config
      assert_equal tmpdir, store.config.dir
      assert_equal true, store.config.versioned

      # Create an item to verify it works
      item = store.item.create!(name: "test")
      assert_equal "test", item.name
    end

    def test_versions_are_readonly
      tmpdir = Dir.mktmpdir

      readonly_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:value)
          end
        end

        record(:record, table: :records)
      end

      store = readonly_store_class.new(dir: tmpdir)

      # Create a record
      record = store.record.transaction { store.record.create!(value: "original") }

      # Modify it
      store.record.transaction { record.update!(value: "updated") }

      # Get the first version (should be readonly)
      v0_record = store.versions[0].record.find(record.id)
      assert v0_record.readonly?

      # Try to update - should raise error
      error = assert_raises(ActiveRecord::ReadOnlyRecord) do
        v0_record.update!(value: "changed")
      end
    end

    def test_config_with_path
      tmpdir = Dir.mktmpdir
      db_path = File.join(tmpdir, "my_custom_db.sqlite3")

      path_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:value)
          end
        end

        record(:record, table: :records)
      end

      store = path_store_class.new(path: db_path)

      # Verify the database is created with the custom name
      assert_equal tmpdir, store.config.dir
      assert_equal "my_custom_db.sqlite3", store.config.db_filename

      # Create a record to verify it works
      record = store.record.transaction { store.record.create!(value: "test") }
      assert_equal "test", record.value

      # Verify the database file exists with the custom name
      assert File.exist?(db_path)
    end

    def test_config_with_dir
      tmpdir = Dir.mktmpdir

      dir_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:value)
          end
        end

        record(:record, table: :records)
      end

      store = dir_store_class.new(dir: tmpdir)

      # Verify the database uses the default name
      assert_equal tmpdir, store.config.dir
      assert_equal "db.sqlite3", store.config.db_filename

      # Create a record to verify it works
      record = store.record.transaction { store.record.create!(value: "test") }
      assert_equal "test", record.value

      # Verify the database file exists with the default name
      assert File.exist?(File.join(tmpdir, "db.sqlite3"))
    end

    def test_config_requires_dir_or_path
      # Should raise when neither is provided
      error = assert_raises(ArgumentError) do
        VersionedStore::Config.new
      end
      assert_match(/Must provide either dir: or path:/, error.message)

      # Should raise when both are provided
      tmpdir = Dir.mktmpdir
      error = assert_raises(ArgumentError) do
        VersionedStore::Config.new(dir: tmpdir, path: File.join(tmpdir, "db.sqlite3"))
      end
      assert_match(/Must provide either dir: or path:, not both/, error.message)
    end

    def test_multiple_databases_in_same_directory
      tmpdir = Dir.mktmpdir

      # Create store class
      multi_store_class = Class.new(VersionedStore::Base) do
        migrate do
          create_table(:records) do |t|
            t.string(:value)
          end
        end

        record(:record, table: :records)
      end

      # Create first database with path
      db1_path = File.join(tmpdir, "first.sqlite3")
      store1 = multi_store_class.new(path: db1_path)

      # Create second database with path in same directory
      db2_path = File.join(tmpdir, "second.sqlite3")
      store2 = multi_store_class.new(path: db2_path)

      # Create records in both databases
      record1 = store1.record.transaction { store1.record.create!(value: "db1_value") }
      record2 = store2.record.transaction { store2.record.create!(value: "db2_value") }

      # Verify each database has its own data
      assert_equal 1, store1.record.count
      assert_equal "db1_value", store1.record.first.value

      assert_equal 1, store2.record.count
      assert_equal "db2_value", store2.record.first.value

      # Verify separate version directories were created
      assert Dir.exist?(File.join(tmpdir, "first_versions"))
      assert Dir.exist?(File.join(tmpdir, "second_versions"))

      # Verify each has its own versions
      assert_equal 1, store1.versions.count
      assert_equal 1, store2.versions.count

      # Create snapshots in both
      store1.snapshot("snapshot1")
      store2.snapshot("snapshot2")

      # Verify separate snapshot directories
      assert Dir.exist?(File.join(tmpdir, "first_snapshots"))
      assert Dir.exist?(File.join(tmpdir, "second_snapshots"))
      assert File.exist?(File.join(tmpdir, "first_snapshots", "snapshot1.sqlite3"))
      assert File.exist?(File.join(tmpdir, "second_snapshots", "snapshot2.sqlite3"))

      # Verify they can restore independently
      store1.record.transaction { record1.update!(value: "db1_updated") }
      restored_store1 = store1.restore("snapshot1")
      assert_equal "db1_value", restored_store1.record.first.value

      # Verify store2 is unaffected
      assert_equal "db2_value", store2.record.first.value
    end
  end
end
