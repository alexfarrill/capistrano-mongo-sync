# capistrano-mongo-sync

Use capistrano-mongo-sync to sync your local development database from
your production database using:

```ruby
cap production mongo:pull
```

Or sync just one collection from the database:

```ruby
COLLECTION=users cap production mongo:pull
```

Or sync your staging database from your production database.

```ruby
cap production mongo:sync_prod_to_staging
```

If you've already downloaded a mongo dump with the
cap task, it will ask you if you'd like to use that local dump.
If someone has already created a mongo dump recently on the remote server,
the cap task will ask if you'd like to use that dump.  Older mongodumps, both
remote and local, will be deleted when you run the cap task.  

## Usage
Add to your Gemfile:

```ruby
gem 'capistrano-mongo-sync'
```

Require in `Capfile` to use the predefined tasks:

```ruby
require 'capistrano/mongo-sync'
```

In deploy.rb, set some variables:

```ruby
set :production_db, 'PRODUCTION_DB'
set :development_db, 'DEVELOPMENT_DB'
```

set some optional variables:
```ruby
set :staging_db, 'STAGING_DB'
```

enable hipchat notifications (requires hipchat gem):
```ruby
set :hipchat_client, HipChat::Client.new('HIPCHAT_TOKEN')
```

enable slack-notifier notifications (requires slack-notifier gem):
```ruby
set :slack_notifier, Slack::Notifier.new("SLACK_WEBHOOK_URL", username: "USERNAME", channel: '#CHANNEL')
```

change database server to take dumps from (useful for syncing from secondary):
```ruby
set :db_role_name, :db_secondary # defaults to :db
```

change where mongodumps are kept remotely and locally:
```ruby
set :remote_dump_base, '/tmp/dumps'
set :local_dump_base, '/tmp/dumps'
```

Or write your own tasks using the MongoSync class
