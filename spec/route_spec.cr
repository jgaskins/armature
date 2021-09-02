require "./spec_helper"

require "../src/route"
require "../src/session"

class RouteTest
  include Armature::Route

  def initialize(&@route : Request, Response, Armature::Session ->)
  end

  def call(context)
    route context do |r, response, session|
      @route.call r, response, session
    end
  end
end

describe Armature::Route do
  it "matches requests to the root route" do
    RouteTest.new do |r, response, session|
      r.on "path" { raise "This is not a request for /path" }

      # A request is not handled at the beginning of the route block
      r.handled?.should eq false

      r.root { }
      # A root request handled by `root` will be marked as handled
      r.handled?.should eq true
    end.call make_context(path: "/")
  end

  it "matches requests to a top-level route" do
    handled = false

    RouteTest.new do |r, response, session|
      r.root { raise "This is not a request to '/'" }

      r.on "top_level" { handled = true }
    end.call make_context(path: "/top_level")

    handled.should eq true
  end

  it "matches requests to nested routes" do
    handled = false

    RouteTest.new do |r, response, session|
      r.on "outer" do
        r.on "inner" do
          handled = true
        end
      end
    end.call make_context(path: "/outer/inner")

    handled.should eq true
  end

  it "matches requests to dynamic routes using symbols" do
    match = nil

    RouteTest.new do |r, response, session|
      r.on "foo" do
        r.on :id { |id| match = id }
      end
    end.call make_context(path: "/foo/bar")

    match.should eq "bar"
  end

  it "matches request methods" do
    method = nil

    RouteTest.new do |r, response, session|
      r.root { raise "This is not a request for '/'" }

      r.on "posts" do
        r.get { raise "This is not a GET request" }
        r.post { method = "post" }
      end
    end.call make_context(method: "POST", path: "/posts")

    method.should eq "post"
  end

  it "marks a request as handled with `is`" do
    # Spec expectations are inside the app
    RouteTest.new do |r, response, session|
      r.root { raise "This is not a request for '/'" }
      r.handled?.should eq false

      r.on "top_level" do
        # `on` does not mark a request as handled
        r.handled?.should eq false

        # `is` does mark a request as handled
        r.is { }

        r.handled?.should eq true
      end
    end.call make_context(method: "GET", path: "/top_level")
  end

  it "treats a trailing slash as if it weren't there" do
    path = nil

    RouteTest.new do |r, response, session|
      r.on "posts" do
        r.on :id do |id|
          r.root { raise "This is not the endpoint" }
          r.on "comments" do
            r.root do
              r.get { path = "comments" }
            end
          end
        end
      end
    end.call make_context(path: "posts/123/comments/")

    path.should eq "comments"
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
