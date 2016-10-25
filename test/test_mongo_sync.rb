require 'minitest/autorun'
require 'mocha/mini_test'

require 'capistrano/mongo_sync/mongo_sync'

class MongoSync
  def fetch(x)
    @remote_dump_base = '/mnt/tmp/dumps'.freeze
    @local_dump_base = '/tmp/dumps'.freeze
    @development_db = 'mydb'.freeze
    @production_db = 'mydb'.freeze
    @staging_db = 'mydb_staging'.freeze
    @from_db = 'mydb'.freeze
    @hipchat_client = nil
    @slack_notifier = nil
    @collection = 'full'

    instance_variable_get("@#{x}")
  end
end

class MongoSyncTest < Minitest::Test
  def setup
    @time_of_run = Time.new(2015, 1, 1, 1, 1)
    Time.stubs(:now).returns(@time_of_run)

    @connection = mock()
    @mongo_sync = MongoSync.new(@connection)
  end

  def test_local_setup
    @connection.expects(:execute).with(:mkdir, '-p', '/tmp/dumps').once()
    @mongo_sync.local_setup!
  end

  def test_local_cleanup
    @connection.expects(:test).with('find /tmp/dumps/* -mtime +1').once().returns(true)
    @connection.expects(:execute).with(:find, '/tmp/dumps/*', '-mtime +1 -exec rm {} \\;').once()
    @mongo_sync.local_cleanup!
  end

  def test_remote_setup
    @connection.expects(:execute).with(:mkdir, '-p', '/mnt/tmp/dumps').once()
    @mongo_sync.remote_setup!
  end

  def test_remote_cleanup
    @connection.expects(:test).with('find /mnt/tmp/dumps/* -mtime +1').returns(true).once()
    @connection.expects(:execute).with(:find, '/mnt/tmp/dumps/*', '-mtime +1 -exec rm {} \\;').once()
    @mongo_sync.remote_cleanup!
  end

  def test_remote_mongodump_full
    @connection.expects(:execute).once().with(:mongodump, '-d', 'mydb', '-o', '/mnt/tmp/dumps/mydb-full-2015-01-01-01-01')
    output_dir = @mongo_sync.remote_mongodump!
    assert_equal 'mydb-full-2015-01-01-01-01', output_dir
  end

  def test_remote_mongodump_agents_collection
    @mongo_sync.instance_variable_set("@collection", 'agents')
    @connection.expects(:execute).once().with(:mongodump, '-d', 'mydb', '-o', '/mnt/tmp/dumps/mydb-agents-2015-01-01-01-01', '-c', 'agents')
    output_dir = @mongo_sync.remote_mongodump!
    assert_equal 'mydb-agents-2015-01-01-01-01', output_dir
  end

  def test_dump_prompt_message
    path_to_tgz = '/tmp/dumps/mydb-full-2015-01-01-01-00.tgz'
    expected_msg = "Use local dump from today at 01:00 AM? \"%s\"? (y/n)" % path_to_tgz
    actual_msg = @mongo_sync.dump_prompt_message :use_local_dump, path_to_tgz
    assert_equal expected_msg, actual_msg
  end

  def test_dump_prompt_accepts_y_n
    path_to_tgz = '/tmp/dumps/mydb-full-2015-01-01-01-00.tgz'

    @mongo_sync.instance_variable_set '@use_local_dump', 'y'
    @mongo_sync.dump_prompt :use_local_dump, path_to_tgz

    @mongo_sync.instance_variable_set '@use_local_dump', 'n'
    @mongo_sync.dump_prompt :use_local_dump, path_to_tgz
  end

  def test_hipchat_notify
    msg = 'Finished syncing prod to staging...'
    opts = { color: 'green' }

    @hipchat_client = mock()
    @mongo_sync.instance_variable_set("@hipchat_client", @hipchat_client)
    @engineering_room = mock()
    @hipchat_client.expects("[]").once().with('Engineering').returns(@engineering_room)
    @engineering_room.expects('capistrano').with(msg, opts)
    @mongo_sync.hipchat_notify! 'Engineering', 'capistrano', msg, opts
  end

  def test_slack_notify
    msg = 'Finished syncing prod to staging...'
    @slack_notifier = mock()
    @mongo_sync.instance_variable_set("@slack_notifier", @slack_notifier)
    @slack_notifier.expects(:ping).with(msg).once
    @mongo_sync.slack_notify! msg
  end


  def test_staging_mongorestore_full_path
    @connection.expects(:execute).once().with(:mongorestore, '--drop', '-d', 'mydb_staging', '/mnt/tmp/dumps/mydb-agents-2015-01-01-01-01/mydb')
    @mongo_sync.staging_mongorestore! '/mnt/tmp/dumps/mydb-agents-2015-01-01-01-01/mydb'
  end

  def test_staging_mongorestore_relative_to_dump_base
    @connection.expects(:execute).once().with(:mongorestore, '--drop', '-d', 'mydb_staging', '/mnt/tmp/dumps/mydb-agents-2015-01-01-01-01/mydb')
    @mongo_sync.staging_mongorestore! 'mydb-agents-2015-01-01-01-01'
  end

  def test_last_remote_dump_no_dumps
    @connection.expects(:test, 'ls -td /mnt/tmp/dumps/*/mydb').returns(false)
    lrd = @mongo_sync.last_remote_dump
    assert_equal nil, lrd
  end

  def test_last_remote_dump_dumps_y
    dumps = %w( /mnt/tmp/dumps/mydb-full-2015-10-07-09-36/mydb /mnt/tmp/dumps/mydb-full-2015-10-07-08-50/mydb ).join("\n")

    @connection.expects(:test, 'ls -td /mnt/tmp/dumps/*').returns(true)
    @connection.expects(:capture).with(:ls, '-td', '/mnt/tmp/dumps/mydb-full*/mydb').returns(dumps)
    @mongo_sync.instance_variable_set '@use_remote_dump_dir', 'y'

    lrd = @mongo_sync.last_remote_dump
    assert_equal '/mnt/tmp/dumps/mydb-full-2015-10-07-09-36/mydb', lrd
  end

  def test_last_remote_dump_dumps_n
    dumps = %w( /mnt/tmp/dumps/mydb-full-2015-10-07-09-36/mydb /mnt/tmp/dumps/mydb-full-2015-10-07-08-50/mydb ).join("\n")

    @connection.expects(:test, 'ls -td /mnt/tmp/dumps/*/mydb').returns(true)
    @connection.expects(:capture).with(:ls, '-td', '/mnt/tmp/dumps/mydb-full*/mydb').returns(dumps)
    @mongo_sync.instance_variable_set '@use_remote_dump_dir', 'n'

    lrd = @mongo_sync.last_remote_dump
    assert_equal nil, lrd
  end

  def test_last_local_dump_no_dumps
    @connection.expects(:test, 'ls -td /mnt/tmp/dumps/mydb-full*/mydb').returns(false)
    lrd = @mongo_sync.last_remote_dump
    assert_equal nil, lrd
  end

  def test_last_remote_dump_tgz
    @connection.expects(:test, 'ls -td /mnt/tmp/dumps/mydb-full*/mydb').returns(false)
    lrd = @mongo_sync.last_remote_dump
    assert_equal nil, lrd
  end

  def test_local_mongorestore
    dump_dir = 'mydb-full-2015-10-07-09-36'
    @connection.expects(:within).with('/tmp/dumps').once.yields
    Dir.expects(:glob).returns(['mydb-full-2015-10-07-09-36/mydb/cat.bson', 'mydb-full-2015-10-07-09-36/mydb/dog.bson'])
    @connection.expects(:execute).with(:mongorestore, '--drop', '-d', 'mydb', 'mydb-full-2015-10-07-09-36/mydb/cat.bson').once
    @connection.expects(:execute).with(:mongorestore, '--drop', '-d', 'mydb', 'mydb-full-2015-10-07-09-36/mydb/dog.bson').once
    @mongo_sync.local_mongorestore! dump_dir
  end

  def test_local_unarchive_preexisting
    tgz = 'mydb-full-2015-10-07-09-36.tgz'
    local_dump_dir = '/tmp/dumps/mydb-full-2015-10-07-09-36'
    @connection.expects(:test).with("ls #{local_dump_dir}").once.returns(true)
    @mongo_sync.local_unarchive! tgz
  end

  def test_local_unarchive_need_to_download
    tgz = 'mydb-full-2015-10-07-09-36.tgz'
    local_dump_dir = '/tmp/dumps/mydb-full-2015-10-07-09-36'
    @connection.expects(:test).with("ls #{local_dump_dir}").once.returns(false)
    @connection.expects(:within).with('/tmp/dumps').once.yields
    @connection.expects(:execute).with(:tar, '-xzvf', tgz).once
    @mongo_sync.local_unarchive! tgz
  end

  def test_remote_archive
    dump_dir = 'mydb-full-2015-10-07-09-36'
    @connection.expects(:within).with('/mnt/tmp/dumps').once.yields
    @connection.expects(:execute).with(:tar, '-czvf', 'mydb-full-2015-10-07-09-36.tgz', 'mydb-full-2015-10-07-09-36').once
    @mongo_sync.remote_archive! dump_dir
  end

end
