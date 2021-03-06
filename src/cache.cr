require "msgpack"
require "log"
require "redis"

module Armature
  class_property! cache : Cache::CacheStore

  module Cache
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
        @log = Log.for(self.class)
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
    end

    extend self

    def cache(key : String, expires_in : Time::Span?, io : IO, & : IO ->)
      if value = ::Armature.cache[key]?
        LOG.debug { "hit #{key.inspect}" }
        case value
        when String
          io << value
        when Bytes
          io.write value
        end
      else
        LOG.debug { "miss #{key.inspect}" }
        buffer = IO::Memory.new
        yield buffer
        LOG.debug { "caching #{key.inspect}: #{buffer.rewind}" }
        ::Armature.cache.write key, buffer.rewind.to_s, expires_in: expires_in
        IO.copy buffer.rewind, io
      end
    end

    def cache
      ::Armature.cache
    end
  end
end
