#!/usr/bin/env ruby

ENV["RUBY_ENV"] = "test"

require 'redis'
require 'pathname'
require_relative '../files'

describe "run link management" do
  before :each do
    @redis = Redis.new(host: $APP_CONFIG["redis"]["host"], db: $APP_CONFIG["redis"]["db"])
    @redis.flushdb

    @files = Files.new
  end

  after :each do
    Dir.glob($APP_CONFIG["destination_path"]+"*/*/*").each do |file| 
      if(Pathname.new(file).symlink?)
        FileUtils.rm(file)
      end
    end
  end

  it "should generate link and set expire" do
    @redis.set("File:LINK:STORE:GUB0100100", nil)
    @files.run
    expect(@redis.get("File:LINK:STORE:GUB0100100")).to_not be_empty
    expect(@redis.get("File:EXPIRE:STORE:GUB0100100")).to_not be_nil
    url = @redis.get("File:LINK:STORE:GUB0100100")
    link_hash = @files.hash_from_url(url)
    hash_path_prefix = @files.hash_path_prefix(link_hash)
    hash_path = hash_path_prefix+"/"+link_hash
    expect(Pathname.new($APP_CONFIG["destination_path"]+"/"+hash_path).symlink?).to be_truthy
    expect(File.read($APP_CONFIG["destination_path"]+"/"+hash_path+"/pdf/GUB0100100.pdf")).to eq("testdata\n")
  end

  it "should append extension to link and url if file" do
    @redis.set("File:LINK:STORE:GUB0100100/pdf/GUB0100100.pdf", nil)
    @files.run
    expect(@redis.get("File:LINK:STORE:GUB0100100/pdf/GUB0100100.pdf")).to_not be_empty
    expect(@redis.get("File:EXPIRE:STORE:GUB0100100/pdf/GUB0100100.pdf")).to_not be_nil
    url = @redis.get("File:LINK:STORE:GUB0100100/pdf/GUB0100100.pdf")
    link_hash = @files.hash_from_url(url)
    hash_path_prefix = @files.hash_path_prefix(link_hash)
    hash_path = hash_path_prefix+"/"+link_hash
    expect(Pathname.new($APP_CONFIG["destination_path"]+"/"+hash_path).symlink?).to be_truthy
    expect(File.read($APP_CONFIG["destination_path"]+"/"+hash_path)).to eq("testdata\n")
  end

  it "should not generate new link when link exists and expire not met" do
    @redis.set("File:LINK:STORE:GUB0100100", nil)
    @files.run
    url = @redis.get("File:LINK:STORE:GUB0100100")
    @files.run
    expect(@redis.get("File:LINK:STORE:GUB0100100")).to eq(url)
  end

  it "should generate new link when link expired" do
    @redis.set("File:LINK:STORE:GUB0100100", nil)
    @files.run
    url = @redis.get("File:LINK:STORE:GUB0100100")
    @redis.set("File:EXPIRE:STORE:GUB0100100", Time.now - 10)
    @files.run
    expect(@redis.get("File:LINK:STORE:GUB0100100")).to_not eq(url)
  end

  it "should store old link as delete_pending when replacing expired link" do
    @redis.set("File:LINK:STORE:GUB0100100", nil)
    @files.run
    url = @redis.get("File:LINK:STORE:GUB0100100")
    link_hash = @files.hash_from_url(url)
    hash_path_prefix = @files.hash_path_prefix(link_hash)
    hash_path = hash_path_prefix+"/"+link_hash
    @redis.set("File:EXPIRE:STORE:GUB0100100", Time.now - 10)
    @files.run
    expect(@redis.get("File:DELETE_PENDING:#{link_hash}")).to_not be_nil
    expect(Pathname.new($APP_CONFIG["destination_path"]+"/"+hash_path).symlink?).to be_truthy
  end

  it "should remove links that were pending and have expired" do
    @redis.set("File:LINK:STORE:GUB0100100", nil)
    @files.run
    url = @redis.get("File:LINK:STORE:GUB0100100")
    link_hash = @files.hash_from_url(url)
    hash_path_prefix = @files.hash_path_prefix(link_hash)
    hash_path = hash_path_prefix+"/"+link_hash
    @redis.set("File:EXPIRE:STORE:GUB0100100", Time.now - 10)
    @files.run
    @redis.set("File:DELETE_PENDING:#{link_hash}", Time.now - 10)
    @files.run
    expect(@redis.get("File:DELETE_PENDING:#{link_hash}")).to be_nil
    expect(Pathname.new($APP_CONFIG["destination_path"]+"/"+hash_path).symlink?).to be_falsey
  end
end

