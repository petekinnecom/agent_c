# frozen_string_literal: true

module VersionedStore
  Config = Data.define(:dir, :db_filename, :logger, :versioned) do
    def initialize(dir: nil, path: nil, logger: nil, versioned: true, db_filename: nil)
      raise ArgumentError, "Must provide either dir: or path:, not both" if dir && path
      raise ArgumentError, "Must provide either dir: or path:" unless dir || path

      db_filename ||= (
        if path
          dir = File.dirname(path)
          db_filename = File.basename(path)
        else
          db_filename = "db.sqlite3"
        end
      )

      super(
        dir:,
        db_filename:,
        logger:,
        versioned:
      )
    end
  end
end
