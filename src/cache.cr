require "msgpack"
require "log"

module Armature
  class_property! cache : Cache::CacheStore

  module Cache
    LOG = ::Log.for(self)

    module CacheStore
      abstract def []?(key : String, as type : T.class) forall T
      abstract def delete(key : String) : Nil
      abstract def write(key : String, value : T, expires_in : Time::Span?) forall T

      def []=(key : String, value : T) : Nil forall T
        write key, value, expires_in: @default_expiration
      end

      def fetch(key : String, expires_in duration : Time::Span?, & : -> T) forall T
        begin
          value = self[key, as: T]?
        rescue
          # If we can't get the value from the cache, the cache server is likely
          # down so we just go ahead yield the block.
          return yield
        end

        if value
          value
        else
          value = yield
          write key, value, expires_in: duration
          value
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
