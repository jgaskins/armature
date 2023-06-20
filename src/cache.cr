require "msgpack"
require "log"
require "redis"

module Armature
  class_property! cache : Cache::CacheStore

  module Cache
    LOG = ::Log.for(self)
    module CacheStore
      abstract def []?(key : String, as type : T.class) forall T
      abstract def []=(key : String, value : T) : Nil forall T
      abstract def delete(key : String) : Nil
    end

    class RedisStore
      include CacheStore

      def initialize(
        @redis : Redis::Client,
        @default_expiration : Time::Span = 1.day,
        @log = Log.for("armature.cache")
      )
      end

      def []?(key : String, as type : T.class) : T? forall T
        if value = @redis.get(key)
          T.from_msgpack value
        end
      end

      def []=(key : String, value : T) : Nil forall T
        write key, value, expires_in: @default_expiration
      end

      def delete(key : String) : Nil
        @redis.del key
      end

      def write(key : String, value : T, expires_in duration : Time::Span?) forall T
        string = String.build { |str| value.to_msgpack str }
        @redis.set key, string, ex: duration
      end

      def fetch(key : String, expires_in duration : Time::Span?, & : -> T) forall T
        if value = self[key, as: T]?
          value
        else
          value = yield
          write key, value, expires_in: duration
          value
        end
      end

      def fetch_all(keys : Array(String), as type : T.class) : Array(T?) forall T
        return [] of T? if keys.empty?

        @redis.mget(keys).as(Array).map do |value|
          if value
            T.from_msgpack value.as(String)
          end
        end
      end
    end

    extend self

    def cache(key : String, expires_in : Time::Span?, io : IO, & : IO ->) : Nil
      if value = ::Armature.cache[key, as: String]?
        LOG.debug &.emit "hit", key: key
        case value
        when String
          io << value
        when Bytes
          io.write value
        end
      else
        LOG.debug &.emit "miss", key: key
        buffer = IO::Memory.new
        writer = IO::MultiWriter.new(io, buffer)
        yield writer.as(IO)
        LOG.debug &.emit "writing", key: key, entry_size: buffer.bytesize
        ::Armature.cache.write key, buffer.to_s, expires_in: expires_in
      end
    end

    def cache
      ::Armature.cache
    end
  end
end
