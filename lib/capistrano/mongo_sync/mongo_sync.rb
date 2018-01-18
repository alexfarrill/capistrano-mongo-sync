require 'digest'

class MongoSync
  def initialize(connection)
    @connection = connection
    @remote_dump_base = fetch(:remote_dump_base)
    @local_dump_base = fetch(:local_dump_base)
    @production_db = fetch(:production_db)
    @development_db = fetch(:development_db)
    @staging_db = fetch(:staging_db)
    @from_db = fetch(:from_db)
    @collection = fetch(:collection) || 'full'
    @collection_ids = fetch(:collection_ids)
    @hipchat_client = fetch(:hipchat_client)

    fail "Incomplete configuration: missing remote_dump_base" unless @remote_dump_base
    fail "Incomplete configuration: missing local_dump_base" unless @local_dump_base
    fail "Incomplete configuration: missing production_db" unless @production_db
    fail "Incomplete configuration: missing development_db" unless @development_db
    fail "Incomplete configuration: missing from_db" unless @from_db
    fail "Incomplete configuration: missing collection" if @collection_ids && @collection.nil?
  end

  # the first part of the dump dir, without the timestamp... for example "mydatabase-full"
  def dump_dir_part
    str = [@from_db, @collection].join('-')

    if @collection_ids
      str = [str, Digest::MD5.hexdigest(@collection_ids)].join('-')
    end

    str
  end

  ## Remote
  def remote_setup!
    @connection.execute :mkdir, '-p', @remote_dump_base
  end

  def remote_cleanup!
    pattern = File.join(@remote_dump_base, '*')

    if @connection.test "find #{pattern} -mtime +1"
      @connection.execute :find, pattern, "-mtime +1 -exec rm {} \\;"
    end
  end

  def remote_mongodump!
    dump_dir = [dump_dir_part, Time.now.strftime('%Y-%m-%d-%H-%M')].join('-')

    args = ['-d', @from_db, '-o', File.join(@remote_dump_base, dump_dir)]
    args += ['-c', @collection] unless 'full' == @collection
    args += ['-q', collection_ids_arg] if @collection_ids

    @connection.execute :mongodump, *args

    dump_dir
  end

  def collection_ids_arg
    '\'{_id: {$in: [%s]}}\'' % @collection_ids.split(',').map{|id| 'ObjectId("%s")' % id}.join(',')
  end

  def staging_mongorestore!( remote_dump_dir )
    full_path_to_remote_dump_dir = if remote_dump_dir == File.basename(remote_dump_dir)
      File.join(@remote_dump_base, remote_dump_dir, @production_db)
    else
      remote_dump_dir
    end

    args = []
    args << '--drop' if drop_collection?
    args += ['-d', @staging_db, full_path_to_remote_dump_dir]
    @connection.execute :mongorestore, *args
  end

  def last_remote_dump
    previous_remote_dump_dirs_wildcard = File.join @remote_dump_base, '%s*/%s' % [dump_dir_part, @production_db]

    if @connection.test( "ls -td #{previous_remote_dump_dirs_wildcard}" )
      dump_candidate = @connection.capture(:ls, '-td', previous_remote_dump_dirs_wildcard).split("\n")[0]

      dump_prompt(:use_remote_dump_dir, dump_candidate)

      if 'y' == fetch(:use_remote_dump_dir)
        dump_candidate
      else
        nil
      end
    else
      nil
    end
  end

  def last_remote_dump_tgz
    previous_remote_dump_tgz_wildcard = '%s*.tgz' % File.join( @remote_dump_base, dump_dir_part )

    if @connection.test "ls -t #{previous_remote_dump_tgz_wildcard}"
      dump_candidate = @connection.capture(:ls, '-t', previous_remote_dump_tgz_wildcard).split("\n")[0]
      dump_prompt(:use_remote_dump_tgz, dump_candidate)

      if 'y' == fetch(:use_remote_dump_tgz)
        dump_candidate
      else
        nil
      end
    else
      nil
    end
  end

  def remote_archive!( dump_dir )
    tar_filename = '%s.tgz' % dump_dir
    @connection.within( @remote_dump_base ) do
      @connection.execute :tar, '-czvf', tar_filename, dump_dir
    end
    File.join @remote_dump_base, tar_filename
  end

  ## Local
  def local_setup!
    @connection.execute :mkdir, '-p', @local_dump_base
  end

  def local_cleanup!
    pattern = File.join(@local_dump_base, '*')

    if @connection.test "find #{pattern} -mtime +1"
      @connection.execute :find, pattern, "-mtime +1 -exec rm {} \\;"
    end
  end

  def last_local_dump
    pattern = File.join(@local_dump_base, '%s*.tgz' % dump_dir_part)

    if @connection.test "ls #{pattern}"
      local_dump_candidate = @connection.capture(:ls, '-td', pattern).split("\n")[0]

      dump_prompt(:use_local_dump, local_dump_candidate)

      if 'y' == fetch(:use_local_dump)
        local_dump_candidate
      else
        nil
      end
    else
      nil
    end
  end

  def local_unarchive!(local_tgz)
    local_dump_dir = File.join @local_dump_base, File.basename(local_tgz, '.tgz')
    if @connection.test("ls #{local_dump_dir}")
      # warn "Skipping untar and instead using previously unpacked dump_dir #{local_dump_dir}"
    else
      @connection.within( @local_dump_base ) do
        @connection.execute :tar, '-xzvf', local_tgz
      end
    end
  end

  def local_mongorestore!(local_dump_dir)
    db_dump_path = File.join local_dump_dir, @from_db
    @connection.within( @local_dump_base ) do
      args = []
      args << '--drop' if drop_collection?
      args += ['-d', @development_db, db_dump_path]
      @connection.execute :mongorestore, *args
    end
  end

  # don't drop the collection if it's importing partially
  def drop_collection?
    @collection_ids.nil?
  end

  ## Hipchat
  def hipchat_notify!( room, user, msg, opts = {} )
    return unless @hipchat_client
    @hipchat_client[room].send(user, msg, opts)
  end

  ## Utility
  def dump_prompt_message( gvar, filename )
    dump_tstamp = filename[/(\d{4}-\d{2}-\d{2}-\d{2}-\d{2})/, 1]
    dump_time = Time.new(*dump_tstamp.split('-'))

    fmt = if dump_time.strftime('%D') == Time.now.strftime('%D')
      'today at %I:%M %p'
    elsif dump_time.strftime('%D') == (Time.now - 24 * 60 * 60).strftime('%D')
      'yesterday at %I:%M %p'
    else
      '%B %d, %Y at %I:%M %p'
    end

    dump_time_human = dump_time.strftime(fmt)

    local_remote = gvar.to_s =~ /local/ ? 'local' : 'remote'
    'Use %s dump from %s? "%s"? (y/n)' % [local_remote, dump_time_human, filename]
  end

  def dump_prompt( gvar, filename )
    return false unless filename

    until fetch(gvar) =~ /\A[yn]\Z/
      @connection.ask(gvar, dump_prompt_message(gvar, filename))
    end
  end
end
