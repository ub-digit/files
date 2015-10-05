#!/usr/bin/env ruby

require 'redis'
require 'digest/sha1'
require 'time'
require 'fileutils'
require_relative 'config'

class Files
  EXPIRE_TIME = 24*24*60 # 24 hours in seconds
  HASH_LENGTH = 16

  def initialize
    @redis = Redis.new(host: $APP_CONFIG["redis"]["host"], db: $APP_CONFIG["redis"]["db"])
  end

  def run
    @redis.keys("File:LINK:*").each do |link_key| 
      if @redis.get(link_key).empty?
        generate_link(link_key)
      else
        # Check for expire date
        if link_expired?(link_key)
          generate_link(link_key)
        end
      end
    end

    @redis.keys("File:DELETE_PENDING:*").each do |delete_key| 
      delete_link_if_expired(delete_key)
    end
  end

  def link_expired?(redis_link_key)
    path = redis_link_path(redis_link_key)
    expire_date = @redis.get("File:EXPIRE:#{path}")
    if expire_date.empty?
      raise StandardError, "This should not happen (no EXPIRE expire_date) [#{redis_link_key}]"
    end
    timestamp = Time.parse(expire_date)
    return false if(timestamp > Time.now)
    true
  end

  def redis_link_path(redis_link_key)
    redis_link_key.scan(/^File:[^:]+:(.*)/).first.first
  end

  def generate_link(redis_link_key)
    path = redis_link_path(redis_link_key)
    expire_date = Time.now + EXPIRE_TIME
    link_hash = generate_hash(path)
    url = $APP_CONFIG["base_url"] + "/" + link_hash

    if !@redis.get(redis_link_key).empty?
      old_url = @redis.get(redis_link_key)
      old_hash = hash_from_url(old_url)
      @redis.set("File:DELETE_PENDING:#{old_hash}", Time.now + EXPIRE_TIME)
    end
    @redis.set("File:EXPIRE:#{path}", expire_date)
    generate_filesystem_symlink(link_hash, path)
    url_extension = get_link_extension(path)
    @redis.set(redis_link_key, url + url_extension)
  end

  def generate_hash(path)
    Digest::SHA1.hexdigest(path + Time.now.to_f.to_s)[0..HASH_LENGTH-1]
  end

  def hash_from_url(url)
    base_url = $APP_CONFIG["base_url"]
    url[base_url.size+1..-1]
  end
  
  def delete_link_if_expired(delete_key)
    link_hash = redis_link_path(delete_key)
    expire_date = @redis.get(delete_key)
    if expire_date.empty?
      raise StandardError, "This should not happen (no DELETE_PENDING expire_date) [#{redis_link_key}]"
    end
    timestamp = Time.parse(expire_date)
    return if(timestamp > Time.now)
    FileUtils.rm($APP_CONFIG["destination_path"]+"/#{link_hash}")
    @redis.del(delete_key)
  end

  def generate_filesystem_symlink(link_hash, path)
    dest = $APP_CONFIG["destination_path"]+"/"+link_hash
    local_path = full_local_path(path)
    if !File.exist?(local_path)
      raise StandardError, "Invalid path: #{path}"
    end
    extension = get_link_extension(path)
    FileUtils.ln_s(local_path, dest+extension)
  end

  def get_link_extension(path)
    extension = ""
    if linking_to_file?(path)
      extension = path[/(\.[^\.]+)$/,1]
    end
    extension
  end

  def linking_to_file?(path)
    File.file?(full_local_path(path))
  end

  def full_local_path(path)
    section,subpath = path.scan(/^([^:]+):(.*)/).first
    section_path = $APP_CONFIG["source_paths"][section]
    if !section_path
      raise StandardError, "Invalid path section: #{path}"
    end
    "#{section_path}/#{subpath}"
  end
end

if __FILE__ == $0
  files = Files.new
  files.run
end
