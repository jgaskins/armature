require "./spec_helper"
require "http"

require "../src/redis_session"

redis = Redis::Client.new
session_store = Armature::Session::RedisStore.new(
  key: "armature-session",
  redis: redis,
  expiration: 1.minute,
)

describe Armature::Session::RedisStore do
  before_each { session_store.next = nil }

  it "deserializes session data as JSON" do
    id = UUID.random.to_s
    redis.set "armature-session-#{id}", {user_id: "my-id"}.to_json, ex: 1.minute

    context = make_context(request_headers: HTTP::Headers{"Cookie" => "armature-session=#{id}"})
    session_store.call context
    context.response.flush

    context.session["user_id"].should eq "my-id"
  end

  it "serializes updated session data as JSON" do
    id = UUID.random.to_s
    context = make_context(request_headers: HTTP::Headers{"Cookie" => "armature-session=#{id}"})
    session_store.next = ->(context : HTTP::Server::Context) do
      context.session["user_id"] = "my-id"
    end

    session_store.call context

    redis.get("armature-session-#{id}").should eq({user_id: "my-id"}.to_json)
  end
end

private def make_context(method = "GET", path = "/", request_body = nil, request_headers = HTTP::Headers.new, response_headers = HTTP::Headers.new, response_body = nil)
  response_io = IO::Memory.new
  context = HTTP::Server::Context.new(
    request: HTTP::Request.new(
      method: method,
      resource: path,
      body: request_body,
      headers: request_headers,
    ),
    response: HTTP::Server::Response.new(response_io),
  )

  context
end
