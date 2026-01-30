# frozen_string_literal: true

require "set"
module VersionedStore
  module Stores
    class Schema
      Record = Data.define(:name, :table, :blocks)
      Migration = Data.define(:version, :block)

      class RecordContext
        attr_reader :schema_instance, :table_name, :record_name

        def initialize(schema_instance, record_name)
          @schema_instance = schema_instance
          @record_name = record_name
          @table_name = nil
        end

        def schema(table_name = nil, &block)
          # If no table name provided, infer from record name
          if table_name.nil?
            name_str = record_name.to_s
            table_name = (name_str.end_with?('s') ? name_str : "#{name_str}s").to_sym
          end

          # Store the table name for later use
          @table_name = table_name

          # Collect all schema blocks for a table
          schema_instance.schema_blocks[table_name] ||= []
          schema_instance.schema_blocks[table_name] << block if block
        end

        def method_missing(...)
        end

        def respond_to_missing?(...)
          true
        end
      end

      attr_reader :migrations, :records, :migrated_tables, :schema_blocks, :post_init_hooks
      def initialize
        @migrations = []
        @records = {}
        @migration_counter = 1
        @migrated_tables = Set.new
        @schema_blocks = {}
        @post_init_hooks = []
      end

      def dup
        new_schema = Schema.new
        new_schema.instance_variable_set(:@migrations, @migrations.dup)
        new_schema.instance_variable_set(:@records, @records.dup)
        new_schema.instance_variable_set(:@migration_counter, @migration_counter)
        new_schema.instance_variable_set(:@migrated_tables, @migrated_tables.dup)
        new_schema.instance_variable_set(:@schema_blocks, @schema_blocks.dup)
        new_schema.instance_variable_set(:@post_init_hooks, @post_init_hooks.dup)
        new_schema.instance_variable_set(:@dir, @dir)
        new_schema
      end

      def dir(path = nil)
        @dir = path if path
        @dir
      end

      def migrate(version = @migration_counter += 1, &block)
        migrations << Migration.new(version: version, block: block)
      end

      def prepend_migration(version, &block)
        migrations.unshift(Migration.new(version: version, block: block))
      end

      def record(name, table: nil, &block)
        # If block is given, execute it in RecordContext to extract schema calls
        extracted_table = table
        if block
          context = RecordContext.new(self, name)
          context.instance_exec(&block)
          extracted_table ||= context.table_name
        end

        prev = records[name]
        blocks = prev ? prev.blocks.dup : []
        blocks << block if block
        # Prefer the first non-nil table name, otherwise default to name + "s"
        table_name = prev&.table || extracted_table
        if table_name.nil?
          name_str = name.to_s
          table_name = (name_str.end_with?('s') ? name_str : "#{name_str}s").to_sym
        end

        records[name] = Record.new(
          name: name,
          table: table_name,
          blocks: blocks
        )
      end

      # Add a migration for each table with collected schema blocks (called after all record blocks)
      def add_table_migrations!
        schema_blocks.each do |table_name, blocks|
          next if migrated_tables.include?(table_name) || table_name.nil?
          blocks_to_eval = blocks.dup
          migration_block = Proc.new do
            create_table(table_name) do |t|
              blocks_to_eval.each { |blk| blk.call(t) }
            end
          end
          version = "table_#{table_name}"
          prepend_migration(version, &migration_block)
          migrated_tables.add(table_name)
        end
      end

      def self.call(&block)
        schema = new
        schema.instance_exec(&block) if block
        schema.add_table_migrations!
        schema
      end
    end
  end
end
