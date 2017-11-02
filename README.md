# Slugbuilder

Slugbuilder is a Ruby gem to build [Heroku](https://www.heroku.com/)-like [slugs](https://devcenter.heroku.com/articles/platform-api-deploying-slugs).

It runs Heroku [buildpacks](https://devcenter.heroku.com/articles/buildpacks) on an application and builds a [slug](https://devcenter.heroku.com/articles/slug-compiler), which is essentially a `tar` file that can run on services like Heroku, [panoplymedia/slugrunner](https://github.com/panoplymedia/slugrunner), [lxfontes/slugrunner-rb](https://github.com/lxfontes/slugrunner-rb), [deis/slugrunner](https://github.com/deis/slugrunner), and the like.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'slugbuilder'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install slugbuilder

## Usage

### Basic Usage

```ruby
# basic
sb = Slugbuilder::Builder.new(repo: 'heroku/node-js-sample', git_ref: 'master')
sb.build # builds the slug `heroku.node-js-sample.master.tgz` in the current directory
```

### Override Slug Name

```ruby
# with environment variables
sb = Slugbuilder::Builder.new(repo: 'heroku/node-js-sample', git_ref: 'master')
sb.build(slug_name: 'my_slug') # builds slug to `my_slug.tgz'
```

### Setting Build Environment

```ruby
# with environment variables
sb = Slugbuilder::Builder.new(repo: 'heroku/node-js-sample', git_ref: 'master')
sb.build(env: {NODE_ENV: 'production', SETTING: 'something'})
```

### Build without Cache

```ruby
# clear cache
sb = Slugbuilder::Builder.new(repo: 'heroku/node-js-sample', git_ref: 'master')
sb.build(clear_cache: true)
```

### Prebuild/Postbuild Hooks

```ruby
# prebuild/postbuild
# using a Proc or Proc-like object (responds to `call` method)
sb = Slugbuilder::Builder.new(repo: 'heroku/node-js-sample', git_ref: 'master')
class PostBuildInterface
  def self.call(repo:, git_ref:, git_url:, stats:, slug:)
    # postbuild logic
  end
end
sb.build(prebuild: ->(repo: repo, git_ref: git_ref, git_url: git_url) { p "prebuild logic" }, postbuild: PostBuildInterface)

# prebuild/postbuild with optional blocks
sb = Slugbuilder::Builder.new(repo: 'heroku/node-js-sample', git_ref: 'master') do |args|
  # prebuild logic
  p args[:repo]
end
sb.build(env: {}) do |args|
  # postbuild logic
  p args[:slug]
end
```

You can optionally define a `pre-compile` or `post-compile` script in your application's `bin` folder (eg. `bin/pre-compile`). The `pre-compile` script will run before any buildpacks are run, and the `post-compile` script will run after all of the buildpacks are run. The script should be executable (run `chmod +x` on the script files).

## API

### Builder#initialize(repo:, git_ref:, &block)

- `repo` String (required): the github repo in the form `<organization>/<repository_name>`, `https://<git_service>/<organization>/<repository_name>.git`, or `git@<git_service>:<organization>/<repository_name>.git`
- `git_ref` String (required): the SHA or branch to build
- `stdout` IO (optional): the IO stream to write build output to. This defaults to `$stdout`
- `block` Block (optional): an optional block that runs pre-build. It receives a Hash with the structure:
  - `repo` String: The git repo identifier in the form `<organization>/<repository_name>`
  - `git_ref` String: The git branchname or SHA
  - `git_url` String: The git URL (this will be in the form specified by the `Slugbuilder.config.protocol`)

Alternatively, a Proc can be passed to `build` method's keyword argument `prebuild` to achieve the same effect.

### Builder#build(slug_name: nil, clear_cache: false, env: {}, buildpacks: Slugbuilder.config.buildpacks, prebuild: nil, postbuild: nil, &block)

`build` builds the slug and writes build information to `STDOUT`.

- `slug_name` String (optional): Override default name of slug (repo.git_ref.git_sha.random_hex.tgz with the `/` in repo replaced by `.`)
- `clear_cache` Boolean (optional): destroys the cache before building when true
- `env` Hash (optional): an optional hash of environment variables
- `buildpacks` Array (optional): optionally set buildpacks to be used for that particular build. defaults to `Slugbuilder.config.buildpacks`. Buildpacks should be in the form `<organization>/<repository_name>`, `https://<git_service>/<organization>/<repository_name>.git`, or `git@<git_service>:<organization>/<repository_name>.git`
- `prebuild` Proc (optional): an optional Proc (or anything that conforms to the `call` API of a Proc) that will be run before the build. The Proc will receive a Hash with the structure:
  - `repo` String: The git repo identifier
  - `git_ref` String: The git branchname or SHA
  - `git_url` String: The git URL (this will be in the form specified by the `Slugbuilder.config.protocol`)
Alternatively, a block can be passed to the `initialize` method to the same effect.
- `postbuild` Proc (optional): an optional Proc (or anything that conforms to the `call` API of a Proc) that will run post-build. The Proc will receive a Hash with the structure:
  - `slug` String: Location of the built slug file
  - `repo` String: The git repo identifier
  - `git_ref` String: The git branchname or SHA
  - `git_url` String: The git URL (this will be in the form specified by the `Slugbuilder.config.protocol`)
  - `git_sha` String: The git SHA (even if the git ref was a branch name)
  - `request_id` String: The unique id of the build request
  - `stats` Hash:
    - setup `Float`: Amount of time spent in setup
    - build `Float`: Total amount of time spent in build (compile/build/slug)
    - compile `Float`: Amount of time spent in buildpack compilation
    - slug `Float`: Amount of time compressing the slug
    - output `String`: Build output to STDOUT

Alternatively, a block can be passed to this method to the same effect. (see below)
- `block` Block (optional): an optional block that can be used as an alternative to the `postbuild` Proc argument. This receives the same arguments as `postbuild` (see above)

## Configuration

Configuration settings can be modified within the `Slugbuilder.configure` block. Or set directly off of `Slugbuilder.config`

```ruby
Slugbuilder.configure do |config|
  config.base_dir = '/tmp/slugbuilder'
  config.cache_dir = '/tmp/slugbuilder-cache'
  config.output_dir = './slugs'
end

Slugbuilder.config.base_dir = '/tmp/slugbuilder'
Slugbuilder.config.cache_dir = '/tmp/slugbuilder-cache'
Slugbuilder.config.output_dir = './slugs'
```

### Options
```ruby
@base_dir = '/tmp/slugbuilder'
@cache_dir = '/tmp/slugbuilder-cache'
@output_dir = './slugs'
@git_service = 'github.com'
@protocol = 'https'
@buildpacks = [
  'git@github.com:heroku/heroku-buildpack-nodejs.git',
  'https://github.com/heroku/heroku-buildpack-ruby.git#37ed188'
]
@heroku_stack = 'heroku-16'
```

**base_dir**

This is the base directory that builds and apps are stored in.

> Defaults to `/tmp/slugbuilder`

**cache_dir**

This is the directory where the cache lives.

> Defaults to `/tmp/slugbuilder-cache`

**output_dir**

This is where slug files are built to.

> Defaults to `.` (the current directory)

**git_service**

This is where the git repositories live (github.com, gitlab.com, bitbucket.org, etc)

> Defaults to `github.com`

**protocol**

The protocol that should be used to pull down git repositories (including buildbpacks). This can be either `https` or `ssh`

> Defaults to `https` (also uses `https` if `protocol` is not valid)

**buildpacks**

Buildpacks is an array of valid git clone-able [buildpack](https://devcenter.heroku.com/articles/buildpacks) URLs. Buildpacks should be in the form `<organization>/<repository_name>`, `https://<git_service>/<organization>/<repository_name>.git`, or `git@<git_service>:<organization>/<repository_name>.git`

> Defaults to []

**heroku_stack**

This is a string configuration option that may affect how certain buildpacks run. It is set as the `$STACK` environment variable. See [Heroku's documentation](https://devcenter.heroku.com/articles/stack) for more information about where this comes from. eg: 'heroku-16', 'cedar-14'

> Defaults to 'heroku-16'

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/panoplymedia/slugbuilder. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.


## License

The gem is available as open source under the terms of the [MIT License](http://opensource.org/licenses/MIT).

## Motivation and Thanks

This project is heavily based on [lxfontes/slugbuilder](https://github.com/lxfontes/slugbuilder) and was inspired by projects like:

- [herokuish](https://github.com/gliderlabs/herokuish)
- [deis/slugbuilder](https://github.com/deis/slugbuilder)
- [dokku](https://github.com/dokku/dokku)
