require "./spec_helper"

require "../src/cache"
require "uuid"

redis = Redis::Client.new
cache : Armature::Cache::CacheStore = Armature::Cache::RedisStore.new(
  redis: redis,
  default_expiration: 10.seconds,
)
Armature.cache = cache

describe Armature::Cache do
  it "returns nil when a key is missing" do
    key = UUID.random.to_s
    cache[key, as: String]?.should eq nil
  end

  it "returns the typecasted value when the key exists" do
    key = UUID.random.to_s
    cache[key] = "foo"

    cached_value = cache[key, as: String]?

    cached_value.should be_a String
    cached_value.should eq "foo"
  end

  it "expires values" do
    # Increase this value if this spec becomes flaky
    ttl = 10.milliseconds
    key = UUID.random.to_s
    cache.write key, "value", expires_in: ttl

    cache[key, as: String]?.should eq "value"
    sleep ttl + 1.millisecond
    cache[key, as: String]?.should be_nil
  end

  it "memoizes values with `fetch`" do
    key = UUID.random.to_s
    result = ""
    invocations = 0

    2.times do
      result = cache.fetch(key, expires_in: 1.minute) do
        invocations += 1
        "value"
      end
    end

    result.should eq "value"
    invocations.should eq 1
  end

  it "deletes keys" do
    key = UUID.random.to_s

    cache[key] = "value"
    cache[key, as: String]?.should eq "value"

    cache.delete key

    cache[key, as: String]?.should be_nil
  end

  it "caches data sent to an IO object" do
    key = UUID.random.to_s
    io = IO::Memory.new

    Armature::Cache.cache(key, expires_in: 1.minute, io: io) do |cache|
      cache << "hello"
    end

    io.to_s.should eq "hello"
    cache[key, as: String]?.should eq "hello"
  end
end
