require "../cache"
require "redis"

class Armature::Cache::RedisStore
  include CacheStore

  def initialize(
    @redis : Redis::Client,
    @default_expiration : Time::Span = 1.day,
    @log = Log.for("armature.cache")
  )
  end

  def []?(key : String, as type : T.class) : T? forall T
    if value = @redis.get(key(key))
      T.from_msgpack value
    end
  end

  def delete(key : String) : Nil
    @redis.del key(key)
  end

  def write(key : String, value : T, expires_in duration : Time::Span?) forall T
    string = String.build { |str| value.to_msgpack str }
    @redis.set key(key), string, ex: duration
  end

  def fetch_all(keys : Array(String), as type : T.class) : Array(T?) forall T
    return [] of T? if keys.empty?

    @redis.mget(keys.map { |key| key(key) }).as(Array).map do |value|
      if value
        T.from_msgpack value.as(String)
      end
    end
  end

  private def key(key : String)
    "cache:#{key}"
  end
end
