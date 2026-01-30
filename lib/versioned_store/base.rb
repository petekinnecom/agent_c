# frozen_string_literal: true

require "active_record"

module VersionedStore
  class Base
    class << self
      def inherited(subclass)
        super
        # If parent has a schema, duplicate it for the child
        # Otherwise create a new empty schema
        parent_schema = @schema
        if parent_schema
          subclass.instance_variable_set(:@schema, parent_schema.dup)
        else
          subclass.instance_variable_set(:@schema, Stores::Schema.new)
        end
      end

      def schema
        @schema ||= Stores::Schema.new
      end

      def record(name, table: nil, &block)
        schema.record(name, table: table, &block)
      end

      def migrate(version = nil, &block)
        if version.nil?
          schema.migrate(&block)
        else
          schema.migrate(version, &block)
        end
      end
    end

    attr_reader :schema, :version, :config
    def initialize(version: :root, **config)
      @schema = self.class.schema
      @schema.add_table_migrations!
      @version = version
      @config = Config.new(**config)
      @klasses = {}

      if File.exist?(@config.db_filename)
        @config&.logger&.info("using existing store at: #{@config.db_filename}")
      else
        @config&.logger&.info("creating store at: #{@config.db_filename}")
      end


      # Define accessor methods for each record type
      schema.records.each do |name, spec|
        singleton_class.define_method(name) { class_for(spec) }
      end

      # eagerly construct classes
      schema.records.each_value { class_for(_1) }

      # Run post-initialization hooks for setting up associations
      schema.post_init_hooks.each { |hook| hook.call(self) }
    end

    def transaction(&)
      base_class.transaction(&)
    end

    def dir
      @config.dir
    end

    def versions
      return [self] unless root?

      version_files = Dir.glob(File.join(versions_dir, "*.sqlite3")).sort
      version_files.map do |file|
        version_num = File.basename(file, ".sqlite3").to_i
        self.class.new(version: version_num, **config.to_h)
      end
    end

    def restore(name = nil)
      if name
        # Named snapshot restore
        raise "Can only restore from root store" unless root?

        snapshot_path = File.join(snapshots_dir, "#{name}.sqlite3")
        raise "Snapshot '#{name}' does not exist" unless File.exist?(snapshot_path)

        # Copy the snapshot to the main database
        main_db = File.join(dir, config.db_filename)
        FileUtils.cp(snapshot_path, main_db)

        # Create a new version snapshot of the restored state
        timestamp = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
        version_file = File.join(versions_dir, "#{timestamp}.sqlite3")
        FileUtils.mkdir_p(File.dirname(version_file))
        FileUtils.cp(main_db, version_file)

        # Return a new root store for the restored state
        self.class.new(version:, **config.to_h)
      else
        # Version-based restore (existing behavior)
        raise "Can only restore from a version snapshot, not from root" if root?

        # Copy the version database to the main database
        main_db = File.join(dir, config.db_filename)
        FileUtils.cp(db_path, main_db)

        # Renumber versions: keep all versions up to and including this one,
        # then create a new version snapshot for the restore
        version_files = Dir.glob(File.join(versions_dir, "*.sqlite3")).sort
        version_files.each do |file|
          file_version = File.basename(file, ".sqlite3").to_i
          if file_version > version
            FileUtils.rm(file)
          end
        end

        # Create a new version snapshot of the restored state
        new_version_num = version + 1
        version_file = File.join(versions_dir, "#{new_version_num}.sqlite3")
        FileUtils.cp(main_db, version_file)

        # Return a new root store for the restored state
        self.class.new(version: :root, **config.to_h)
      end
    end

    def snapshot(name)
      raise "Can only create snapshots from root store" unless root?

      # Create snapshots directory if it doesn't exist
      FileUtils.mkdir_p(snapshots_dir)

      # Copy current database to named snapshot
      snapshot_path = File.join(snapshots_dir, "#{name}.sqlite3")
      FileUtils.cp(db_path, snapshot_path)
    end

    private

    def schema_root_mod_name
      @schema_root_mod_name ||+ "SchemaRoot_#{schema.object_id}_#{object_id}"
    end

    def schema_root_mod
      @schema_root_mod ||= (
        if Base.const_defined?(schema_root_mod_name)
          Base.const_get(schema_root_mod_name)
        else
          Module.new.tap { Base.const_set(schema_root_mod_name, _1) }
        end
      )
    end

    def base_class
      @base_class ||= (
        me = self
        klass = Class.new(ActiveRecord::Base) do
          define_singleton_method(:transaction_mutex) do
            @transaction_mutex ||= Mutex.new
          end

          define_singleton_method(:class_name) do |name|
            "#{me.send(:schema_root_mod)}::Record_#{name}"
          end

          define_singleton_method(:store) do
            me
          end

          define_method(:store) do
            self.class.store
          end

          define_singleton_method(:transaction) do |**options, &block|
            # If already in a transaction, just call super without creating a backup
            return super(**options, &block) if connection.transaction_open?

            transaction_mutex.synchronize do
              result = super(**options, &block)

              if me.config.versioned
                timestamp = Process.clock_gettime(Process::CLOCK_REALTIME, :nanosecond)
                backup_path = File.join(me.send(:versions_dir), "#{timestamp}.sqlite3")
                FileUtils.mkdir_p(File.dirname(backup_path))
                FileUtils.cp(me.send(:db_path), backup_path)
              end

              result
            end
          end
        end

        # ActiveRecord doesn't let this be anonymous?
        schema_root_mod.const_set(
          "Base",
          klass
        )

        klass.abstract_class = true
        klass.establish_connection(
          adapter: 'sqlite3',
          database: db_path
        )

        # Configure SQLite to use DELETE journal mode instead of WAL
        # This avoids creating -wal and -shm files
        klass.connection.execute("PRAGMA journal_mode=DELETE")
        klass.connection.execute("PRAGMA locking_mode=NORMAL")

        # Only run migrations for the root store, not for version snapshots
        if root? && schema.migrations.any?
          # Ensure schema_migrations table exists
          unless klass.connection.table_exists?(:schema_migrations)
            klass.connection.create_table(:schema_migrations, id: false) do |t|
              t.string :version, null: false
            end
            klass.connection.add_index(:schema_migrations, :version, unique: true)
          end

          # Run any migrations that haven't been run yet
          schema.migrations.each do |migration|
            version = migration.version.to_s

            # Check if migration has already been run using quote method for SQL safety
            existing = klass.connection.select_value(
              "SELECT 1 FROM schema_migrations WHERE version = #{klass.connection.quote(version)} LIMIT 1"
            )
            next if existing

            # Run the migration
            klass.connection.instance_exec(&migration.block)

            # Record that this migration has been run
            klass.connection.execute(
              "INSERT INTO schema_migrations (version) VALUES (#{klass.connection.quote(version)})"
            )
          end
        end

        klass
      )
    end

    def class_for(spec)
      @klasses[spec.name] ||= (
        store = self
        Class.new(base_class) do
          self.table_name = spec.table

          # Execute all blocks if present, but define a schema method to ignore schema calls
          if spec.blocks && !spec.blocks.empty?
            define_singleton_method(:schema) { |*args, &blk| }
            spec.blocks.each do |blk|
              class_exec(&blk) if blk
            end
            singleton_class.remove_method(:schema) rescue nil
          end

          # Make all records readonly if this is a version snapshot
          if not store.send(:root?)
            define_method(:readonly?) { true }
          end

          # Override polymorphic_name to return simple string name (both instance and class methods)
          simple_name = spec.name.to_s

          define_method(:polymorphic_name) do
            simple_name
          end

          define_singleton_method(:polymorphic_name) do
            simple_name
          end

          # Override polymorphic_class_for to resolve simple names back to classes
          define_singleton_method(:polymorphic_class_for) do |name|
            store.send(:class_for, store.schema.records.fetch(name.to_sym))
          end
        end
      ).tap {
        schema_root_mod.const_set("Record_#{spec.name}", _1)
      }
    end

    def db_prefix
      @db_prefix ||= config.db_filename.sub(/\.sqlite3$/, "")
    end

    def versions_dir
      @versions_dir ||= File.join(dir, "#{db_prefix}_versions")
    end

    def snapshots_dir
      @snapshots_dir ||= File.join(dir, "#{db_prefix}_snapshots")
    end

    def db_path
      @db_path ||= (
        if root?
          File.join(dir, config.db_filename)
        else
          File.join(versions_dir, "#{version}.sqlite3")
        end
      )
    end

    def root?
      version == :root
    end
  end
end
