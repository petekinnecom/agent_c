# VersionedStore

VersionedStore is a versioned SQLite database abstraction built on ActiveRecord that automatically creates snapshots after each transaction. It provides time-travel capabilities, named snapshots, and a clean DSL for defining records and schemas.

## Key Features

- **Automatic Versioning** - Each transaction automatically creates a timestamped snapshot
- **Time Travel** - Access any previous version of your database
- **Named Snapshots** - Create and restore from labeled checkpoints
- **ActiveRecord Integration** - Full ActiveRecord API support (queries, associations, validations)
- **Schema DSL** - Define tables inline with record definitions
- **Additive Schema** - Multiple record blocks merge schemas and behaviors
- **Transaction Safety** - Automatic rollback on errors, no version created on failure
- **Read-Only Versions** - Historical versions are immutable by default

## Quick Start

```ruby
# This loads VersionedStore
# it's a separate gem, but I just inlined it
# in this project for convenience
require 'agent_c'

# Define your store with records
class MyStore < VersionedStore::Base
  record(:author) do
    schema do |t|
      t.string(:name)
      t.string(:email)
    end

    has_many :posts, class_name: class_name(:post)
  end

  record(:post) do
    schema do |t|
      t.string(:title)
      t.text(:content)
      t.integer(:author_id)
    end

    belongs_to :author, class_name: class_name(:author)
  end
end

# Initialize the store
store = MyStore.new( dir: "/tmp/my_data" )

# Create records
author = store.transaction do
  store.author.create!(name: "Jane Doe", email: "jane@example.com")
end

post = store.transaction do
  store.post.create!(
    title: "My First Post",
    content: "Hello world!",
    author: author
  )
end

# Browse versions
puts "Total versions: #{store.versions.count}"
store.versions.each_with_index do |version, i|
  puts "Version #{i}: #{version.author.count} authors, #{version.post.count} posts"
end
```

## Defining Records and Schemas

### Inline Schema Definition

The most common pattern is defining the schema inline with the record:

```ruby
class MyStore < VersionedStore::Base
  record(:user) do
    schema do |t|
      t.string(:name)
      t.string(:email)
      t.integer(:age)
      t.boolean(:active, default: true)
      t.timestamps
    end

    # Add instance methods
    def display_name
      "#{name} <#{email}>"
    end

    # Add class methods via class_eval
    def self.active_users
      where(active: true)
    end
  end
end

store = MyStore.new( dir: "/tmp/users" )
user = store.user.create!(name: "Alice", email: "alice@example.com", age: 30)
puts user.display_name # => "Alice <alice@example.com>"
```

### Explicit Table Names

By default, the table name is inferred by pluralizing the record name (adds 's'). You can specify a custom table name:

```ruby
record(:person, table: :people) do
  schema do |t|
    t.string(:name)
  end
end
```

### Additive Record Blocks

You can define multiple blocks for the same record. They're additive - schemas merge, methods accumulate:

```ruby
record(:user) do
  schema do |t|
    t.string(:name)
  end

  def hello
    "Hello, #{name}!"
  end
end

record(:user) do
  schema do |t|
    t.string(:email)
  end

  def goodbye
    "Goodbye, #{name}!"
  end
end

# Both columns and both methods are available
user = store.user.create!(name: "Bob", email: "bob@example.com")
user.hello    # => "Hello, Bob!"
user.goodbye  # => "Goodbye, Bob!"
```

### Using Migrations

For complex schema changes or when you need more control, use explicit migrations:

```ruby
class MyStore < VersionedStore::Base
  migrate do
    create_table(:users) do |t|
      t.string(:name)
      t.timestamps
    end
  end

  migrate do
    add_column(:users, :email, :string)
    add_index(:users, :email, unique: true)
  end

  record(:user, table: :users) do
    validates :email, uniqueness: true
  end
end
```

## Relationships

VersionedStore supports standard ActiveRecord associations. Use `class_name` helper to reference other record classes:

```ruby
class BlogStore < VersionedStore::Base
  record(:author) do
    schema do |t|
      t.string(:name)
    end

    has_many(
      :posts,
      foreign_key: :author_id,
      class_name: class_name(:post),
      inverse_of: :author
    )
  end

  record(:post) do
    schema do |t|
      t.string(:title)
      t.text(:content)
      t.integer(:author_id)
    end

    belongs_to(
      :author,
      class_name: class_name(:author),
      inverse_of: :posts
    )

    has_many(
      :comments,
      foreign_key: :post_id,
      class_name: class_name(:comment),
      dependent: :destroy
    )
  end

  record(:comment) do
    schema do |t|
      t.text(:body)
      t.integer(:post_id)
    end

    belongs_to(
      :post,
      class_name: class_name(:post)
    )
  end
end

store = BlogStore.new( dir: "/tmp/blog" )

author = store.transaction do
  store.author.create!(name: "Alice")
end

post = store.transaction do
  store.post.create!(
    title: "Hello World",
    content: "My first post",
    author: author
  )
end

comment = store.transaction do
  store.comment.create!(
    body: "Great post!",
    post: post
  )
end

# Use relationships
puts post.author.name           # => "Alice"
puts author.posts.count         # => 1
puts post.comments.first.body   # => "Great post!"
```

## Transactions and Versioning

### Basic Transactions

Every transaction creates a new version snapshot:

```ruby
store = MyStore.new( dir: "/tmp/data" )

store.user.transaction do
  store.user.create!(name: "Alice")
end
# Version 1 created

store.user.transaction do
  store.user.create!(name: "Bob")
end
# Version 2 created

puts store.versions.count # => 2
```

### Nested Transactions

Only the outermost transaction creates a version:

```ruby
store.transaction do
  user1 = store.user.create!(name: "Alice")
  user2 = store.user.create!(name: "Bob")

  store.transaction do
    user1.update!(email: "alice@example.com")
    user2.update!(email: "bob@example.com")
  end
end
# Only 1 version created for the entire transaction
```

### Transaction Rollback

If an error occurs, the transaction rolls back and no version is created:

```ruby
initial_count = store.versions.count

begin
  store.transaction do
    store.user.create!(name: "Alice")
    raise "Something went wrong"
  end
rescue => e
  # Exception caught
end

# No version created - count unchanged
assert_equal initial_count, store.versions.count
```

### Disabling Versioning

For high-volume operations or testing, disable versioning:

```ruby
store = MyStore.new(config: {
  dir: "/tmp/data",
  versioned: false
})

store.user.transaction { store.user.create!(name: "Alice") }
store.user.transaction { store.user.create!(name: "Bob") }

store.versions.count # => 0
```

## Accessing Versions

### Listing Versions

```ruby
store.versions.each_with_index do |version, i|
  puts "Version #{i}:"
  puts "  Users: #{version.user.count}"
  puts "  Posts: #{version.post.count}"
end
```

### Reading from Versions

Version records are read-only:

```ruby
# Get version 0 (first snapshot)
v0 = store.versions[0]

user = v0.user.first
puts user.name

# Versions are read-only
user.readonly? # => true

# This will raise ActiveRecord::ReadOnlyRecord
user.update!(name: "New Name")
```

### Version Relationships

Associations work across versions:

```ruby
# Create author and post
author = store.transaction do
  store.author.create!(name: "Alice")
end

post = store.transaction do
  store.post.create!(title: "Hello", author: author)
end

# Access from version
v1 = store.versions[1]
v1_post = v1.post.first
puts v1_post.author.name # => "Alice"
```

## Named Snapshots

Named snapshots provide labeled checkpoints you can restore to:

```ruby
store = MyStore.new( dir: "/tmp/data" )

# Create initial state
store.user.transaction { store.user.create!(name: "Alice") }

# Create a named snapshot
store.snapshot("initial_state")

# Make more changes
store.user.transaction { store.user.create!(name: "Bob") }
store.user.transaction { store.user.create!(name: "Charlie") }

# Create another snapshot
store.snapshot("three_users")

# Continue working
store.user.transaction { store.user.first.update!(name: "Alice Updated") }

puts store.user.count # => 3

# Restore to "initial_state"
restored_store = store.restore("initial_state")

puts restored_store.user.count # => 1
puts restored_store.user.first.name # => "Alice"
```

## Restoring from Versions

### Version-Based Restore

Restore to a specific version by index:

```ruby
# Create some versions
store.user.transaction { store.user.create!(name: "Alice") }
store.user.transaction { store.user.create!(name: "Bob") }
store.user.transaction { store.user.create!(name: "Charlie") }

# Restore to version 1 (after Bob was added)
restored_store = store.versions[1].restore

restored_store.user.count # => 2
restored_store.user.pluck(:name) # => ["Alice", "Bob"]

# Can continue working from restored state
restored_store.user.transaction do
  restored_store.user.create!(name: "Dave")
end
```

### Named Snapshot Restore

```ruby
store.snapshot("checkpoint")

# Make changes...

# Restore by name
restored_store = store.restore("checkpoint")
```

### How Restore Works

When you restore:
1. The specified version/snapshot is copied to the main database
2. Versions newer than the restored version are removed (for version-based restore)
3. A new version is created of the restored state
4. A new store instance is returned pointing to the restored database

## Configuration

### Directory-Based Configuration

Store the database in a directory with default filename:

```ruby
store = MyStore.new( dir: "/tmp/my_data" )

# Creates:
#   /tmp/my_data/db.sqlite3
#   /tmp/my_data/db_versions/
#   /tmp/my_data/db_snapshots/
```

### Path-Based Configuration

Specify a custom database filename:

```ruby
store = MyStore.new(
  config: { path: "/tmp/my_data/custom.sqlite3"}
)

# Creates:
#   /tmp/my_data/custom.sqlite3
#   /tmp/my_data/custom_versions/
#   /tmp/my_data/custom_snapshots/
```

### Multiple Databases in Same Directory

Use path-based configuration for multiple databases:

```ruby
store1 = MyStore.new( path: "/tmp/data/first.sqlite3" )
store2 = MyStore.new( path: "/tmp/data/second.sqlite3" )

# Creates separate version and snapshot directories:
#   /tmp/data/first.sqlite3
#   /tmp/data/first_versions/
#   /tmp/data/first_snapshots/
#   /tmp/data/second.sqlite3
#   /tmp/data/second_versions/
#   /tmp/data/second_snapshots/
```

### Hash Configuration

Pass configuration as a hash for convenience:

```ruby
store = MyStore.new(config: {
  dir: "/tmp/data",
  logger: Logger.new($stdout),
  versioned: true
})
```

### Configuration Options

```ruby
{
  # Required: specify either dir or path
  dir: "/tmp/data",              # Directory for database
  path: "/tmp/data/db.sqlite3",  # Or full path to database file

  # Optional
  logger: Logger.new($stdout),   # Logger for debugging
  versioned: true                # Enable/disable versioning
}
```

## Accessing Store from Records

Both record classes and instances have access to the store:

```ruby
class MyStore < VersionedStore::Base
  record(:user) do
    schema do |t|
      t.string(:name)
    end

    def create_post(title)
      # Access store from instance
      store.post.create!(title: title, user: self)
    end

    def self.with_posts
      # Access store from class
      joins(:posts).distinct
    end
  end

  record(:post) do
    schema do |t|
      t.string(:title)
      t.integer(:user_id)
    end

    belongs_to :user, class_name: class_name(:user)
  end
end

store = MyStore.new( dir: "/tmp/data" )

user = store.user.create!(name: "Alice")
post = user.create_post("Hello World")

# Class-level store access
store.user.store == store # => true

# Instance-level store access
user.store == store # => true
post.store == store # => true
```

## Advanced Usage

### Custom Validations

```ruby
record(:user) do
  schema do |t|
    t.string(:email)
    t.string(:name)
  end

  validates :email, presence: true, uniqueness: true
  validates :name, length: { minimum: 2 }

  before_save :normalize_email

  private

  def normalize_email
    self.email = email.downcase.strip if email
  end
end

user = store.user.new(name: "A", email: "ALICE@EXAMPLE.COM")
user.valid? # => false
user.errors[:name] # => ["is too short (minimum is 2 characters)"]

user.name = "Alice"
user.save! # email normalized to "alice@example.com"
```

### Scopes and Queries

```ruby
record(:post) do
  schema do |t|
    t.string(:title)
    t.boolean(:published, default: false)
    t.timestamps
  end

  scope :published, -> { where(published: true) }
  scope :recent, -> { order(created_at: :desc).limit(10) }

  def self.by_title(title)
    where("title LIKE ?", "%#{title}%")
  end
end

# Use scopes
published_posts = store.post.published
recent_posts = store.post.recent
search_results = store.post.by_title("Ruby")
```

### JSON and Array Columns

```ruby
record(:user) do
  schema do |t|
    t.json(:preferences, default: {})
    t.json(:tags, default: [])
  end
end

user = store.user.create!(
  preferences: { theme: "dark", language: "en" },
  tags: ["ruby", "rails"]
)

user.preferences["theme"] # => "dark"
user.tags # => ["ruby", "rails"]
```

## Testing with VersionedStore

### Test Setup

```ruby
require "minitest/autorun"
require "agent_c"

class MyTest < Minitest::Test
  def setup
    @store_class = Class.new(VersionedStore::Base) do
      record(:user) do
        schema do |t|
          t.string(:name)
          t.string(:email)
        end
      end
    end

    @store = @store_class.new(dir: Dir.mktmpdir)
  end

  def test_user_creation
    user = @store.user.create!(name: "Alice", email: "alice@example.com")

    assert_equal "Alice", user.name
    assert_equal "alice@example.com", user.email
    assert_equal 1, @store.user.count
  end
end
```

### Testing Versioning

```ruby
def test_versioning
  @store.user.transaction { @store.user.create!(name: "Alice") }
  @store.user.transaction { @store.user.create!(name: "Bob") }

  assert_equal 2, @store.versions.count

  # Version 0 has only Alice
  assert_equal 1, @store.versions[0].user.count
  assert_equal "Alice", @store.versions[0].user.first.name

  # Version 1 has both
  assert_equal 2, @store.versions[1].user.count
end
```

### Testing Restore

```ruby
def test_restore
  user = @store.user.transaction { @store.user.create!(name: "Alice") }
  @store.user.transaction { user.update!(name: "Alice Updated") }

  # Restore to version 0
  restored_store = @store.versions[0].restore

  restored_user = restored_store.user.find(user.id)
  assert_equal "Alice", restored_user.name
end
```

## Common Patterns

### Store as a Mixin

```ruby
module MyApp
  module Store
    extend ActiveSupport::Concern

    included do
      record(:workspace) do
        schema do |t|
          t.string(:dir, null: false)
          t.json(:env, default: {})
        end
      end

      record(:task) do
        schema do |t|
          t.string(:status, default: "pending")
          t.references(:workspace)
        end

        belongs_to :workspace, class_name: class_name(:workspace)
      end
    end
  end
end

class MyStore < VersionedStore::Base
  include MyApp::Store

  record(:user) do
    schema do |t|
      t.string(:name)
    end
  end
end
```

### Polymorphic Associations

```ruby
record(:comment) do
  schema do |t|
    t.text(:body)
    t.string(:commentable_type)
    t.integer(:commentable_id)
  end

  belongs_to(
    :commentable,
    polymorphic: true
  )
end

record(:post) do
  schema do |t|
    t.string(:title)
  end

  has_many(
    :comments,
    as: :commentable,
    class_name: class_name(:comment)
  )
end

# Use polymorphic associations
post = store.post.create!(title: "Hello")
comment = store.comment.create!(body: "Great post!", commentable: post)

comment.commentable == post # => true
post.comments.first == comment # => true
```

## Performance Considerations

1. **Version Size** - Each version is a full database copy. For large databases, consider:
   - Using `versioned: false` for bulk operations
   - Batch multiple operations in a single transaction
   - Periodically clean old versions

2. **Queries** - Standard ActiveRecord performance practices apply:
   - Add indexes for frequently queried columns
   - Use `includes` to avoid N+1 queries
   - Use `find_each` for large result sets

3. **Transactions** - Keep transactions small and focused:
   ```ruby
   # Good: One logical operation
   store.transaction do
     user = store.user.create!(name: "Alice")
     user.posts.create!(title: "Hello")
   end

   # Avoid: Multiple unrelated operations
   store.transaction do
     store.user.create!(name: "Alice")
     store.category.create!(name: "Tech")
     store.setting.update_all(enabled: true)
   end
   ```

## Reseting the Database

You can just delete the directory.

## Troubleshooting

### Version Directory Growing

Old versions are never automatically deleted. Manually clean up:

```ruby
# Remove all but the latest N versions
def cleanup_versions(store, keep_count = 10)
  version_files = Dir.glob(File.join(store.send(:versions_dir), "*.sqlite3")).sort
  to_delete = version_files[0..-(keep_count + 1)]
  to_delete.each { |f| File.delete(f) }
end
```

### Migration Not Running

Migrations only run on root store initialization:

```ruby
# This runs migrations
store = MyStore.new( dir: "/tmp/data" )

# This doesn't run migrations (accessing existing snapshot)
version_store = store.versions[0]
```
