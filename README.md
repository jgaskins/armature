# Armature

Armature is an HTTP routing framework for Crystal.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     armature:
       github: jgaskins/armature
   ```

2. Run `shards install`

## Usage

Armature has 2 primary components:

- `Armature::Route`
  - Provides a routing graph by allowing a top-level application to delegate to various child routes based on path segments
  - Provides an [ECR](https://crystal-lang.org/api/1.0.0/ECR.html) rendering macro to render view templates at compile time. View templates are under the `views/` directory in the application root.
  - Provides a missed-match handler (`r.miss`) so you can provide custom 404 handling in a way that's simple and discoverable
- `Armature::Session`
  - If you're using cookie-based authentication, you can use Armature sessions to persist session data between requests
  - Currently the only supported session adapter is `Armature::Session::RedisStore`. The value stored in the cookie is the session id and the data stored in Redis will be the session data serialized into a JSON string.

```crystal
require "armature"
require "armature/redis_session"
require "redis"

class App
  include HTTP::Handler
  include Armature::Route

  def call(context)
    route context do |r, response, session|
      # The `session` can be treated as a key/value object. All JSON-friendly
      # types can be stored and retrieved. The stored session data is saved as
      # JSON and parsed into a `JSON::Any`.
      if current_user_id = session["user_id"]?.try(&.as_i?)
        current_user = UserQuery.new.find_by_id(current_user_id)
      end

      # `render` macro provided by `Armature::Route` renders the given template
      # inside the `views/` directory to the `response` object. This example
      # renders `views/app_header.ecr`.
      #
      # Note: You can render as many templates as you need, allowing for nesting
      # your UI via nested routes.
      render "app_header"
      
      # Root path (all HTTP verbs)
      r.root do
        # Execute the given block only for GET requests
        r.get { render "homepage" }

        # Execute the given block only for POST requests
        r.post do
          # ...
        end
      end

      # Delegate certain paths to other `Armature::Route`s with `on`
      r.on "products" { Products.new.call(context) }

      # Allow for authenticated-only routes
      if current_user
        r.on "notifications" { Notifications.new(current_user).call(context) }
        r.on "cart" { Cart.new(current_user).call(context) }
      end

      # Execute a block if an endpoint has not been reached yet.
      r.miss do
        response.status = :not_found
        render "not_found"
      end

      # Rendering the footer below main app content
      render "app_footer"
    end
  end
end

http = HTTP::Server.new([
  Armature::Session::RedisStore.new(
    # the HTTP cookie name to store the session id in
    key: "app_session",
    # a client for the Redis instance to store session data in
    redis: Redis::Client.from_env("REDIS_URL"),
  ),
  App.new,
])
http.listen 8080
```

Other useful components are:

- `Armature::Form::Helper`
- `Armature::Cache`
- `Armature::Component`

## Contributing

1. Fork it (<https://github.com/jgaskins/armature/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Jamie Gaskins](https://github.com/jgaskins) - creator and maintainer
