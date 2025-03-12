require "./spec_helper"
require "uuid"

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

  struct CaseInsensitive
    def initialize(@match : String)
    end

    def ===(segment : String)
      if @match.compare(segment, case_insensitive: true) == 0
        segment
      end
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

  it "removes matched segments inside the block and replaces them after the block" do
    reached_endpoint = false

    RouteTest.new do |r|
      r.path.should eq "/outer/inner/endpoint"

      r.on "outer" do
        r.path.should eq "/inner/endpoint"

        r.on "inner" do
          r.path.should eq "/endpoint"
          reached_endpoint = true
        end

        r.path.should eq "/inner/endpoint"
      end

      r.path.should eq "/outer/inner/endpoint"
    end.call make_context(path: "/outer/inner/endpoint")

    reached_endpoint.should eq true
  end

  it "tracks the original request path" do
    RouteTest.new do |r|
      r.on "outer" do
        r.on "inner" do
          r.get "endpoint" do
            r.original_path.should eq "/outer/inner/endpoint"
          end
        end
      end
    end.call make_context(path: "/outer/inner/endpoint")
  end

  it "matches requests to routes with multiple args" do
    handled = false
    count = 0

    RouteTest.new do |r, response, session|
      # We need to be a bit more explicit about this, as previous
      # versions of `on` interpreted multiple args as "any of".
      r.on "outer", "inner" do
        count += 1
        r.is "last" do
          handled = true
        end
      end
    end.call make_context(path: "/outer/inner/last")

    handled.should eq true
    count.should eq 1
  end

  it "captures requests to routes with a '*'" do
    match = nil

    RouteTest.new do |r|
      r.on :id do |id|
        match = id
      end
    end.call make_context(path: "/*")

    match.should eq "*"
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

  it "matches requests to dynamic routes with types" do
    match = nil

    route = RouteTest.new do |r, response, session|
      r.on "foo" do
        r.on id: Int64 do |id|
          match = id
        end
        r.on id: UUID do |id|
          match = id
        end
        r.on id: /@(\w+)/ do |id|
          match = id
        end
        r.on foo: RouteTest::CaseInsensitive.new("hello") do |id|
          match = id
        end
      end
    end
  end

  it "matches requests to dynamic routes with named types" do
    match = nil

    route = RouteTest.new do |r, response, session|
      r.on "foo" do
        r.on id: Int64 do |id|
          match = id
        end
        r.on id: UUID do |id|
          match = id
        end
        r.on id: /@(\w+)/ do |id|
          match = id
        end
        r.on foo: RouteTest::CaseInsensitive.new("hello") do |id|
          match = id
        end
      end
    end

    route.call make_context(path: "/foo/123")
    match.should be_a Int64

    route.call make_context(path: "/foo/#{UUID.random}")
    match.should be_a UUID

    route.call make_context(path: "/foo/@jamie")
    match.should be_a Regex::MatchData
    match.as(Regex::MatchData)[1].should eq "jamie"

    route.call make_context(path: "/foo/hello")
    match.should eq "hello"

    route.call make_context(path: "/foo/HELLO")
    match.should eq "HELLO"
  end

  it "matches static paths with slashes" do
    matched = false

    RouteTest.new do |r|
      r.on "foo/bar" do
        matched = true
      end
    end.call make_context(path: "/foo/bar")

    matched.should eq true
  end

  it "matches requests to dynamic routes with multiple typed args" do
    handled = false
    count = 0

    RouteTest.new do |r, response, session|
      # We need to be a bit more explicit about this, as previous
      # versions of `on` interpreted multiple args as "any of".
      r.on Int64, :thing do |int, thing|
        count += 1
        typeof(int).should eq Int64
        int.should eq 64
        typeof(thing).should eq String
        thing.should eq "string"
      end
    end.call make_context(path: "/64/string")

    count.should eq 1
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

  context "matching only an endpoint with `is`" do
    is_match = false
    is_inner_match = false
    inner_match = false
    route = RouteTest.new do |r|
      r.on "outer" do
        r.is { is_match = true }
        r.on "inner" { inner_match = true }
        r.is "inner" { is_inner_match = true }
      end
    end

    before_each do
      is_match = false
      is_inner_match = false
      inner_match = false
    end

    it "with a path" do
      route.call make_context(path: "/outer/inner")

      is_match.should eq false
      is_inner_match.should eq true
      inner_match.should eq true
    end

    it "matches bare" do
      route.call make_context(path: "/outer")

      is_match.should eq true
      is_inner_match.should eq false
      inner_match.should eq false
    end

    it "does not match if it is not an endpoint" do
      route.call make_context(path: "/outer/inner/endpoint")

      is_match.should eq false
      is_inner_match.should eq false
      inner_match.should eq true
    end
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

  it "matches arguments to `is`" do
    # Spec expectations are inside the app
    RouteTest.new do |r, response, session|
      r.root { raise "This is not a request for '/'" }
      r.handled?.should eq false

      r.on "top_level" do
        # `on` does not mark a request as handled
        r.handled?.should eq false

        # `is` does mark a request as handled
        r.is String, Int64 do |arg, arg2|
          arg.should eq "test"
          arg2.should eq 321
        end

        r.handled?.should eq true
      end
    end.call make_context(method: "GET", path: "/top_level/test/321")
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
