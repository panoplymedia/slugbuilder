# Slugbuilder

Slugbuilder is a Ruby gem to build [Heroku](https://www.heroku.com/)-like [slugs](https://devcenter.heroku.com/articles/platform-api-deploying-slugs).

It runs Heroku [buildpacks](https://devcenter.heroku.com/articles/buildpacks) on an application and builds a [slug](https://devcenter.heroku.com/articles/slug-compiler), which is essentially a `tar` file that can run on services like Heroku, [lxfontes/slugrunner-rb](https://github.com/lxfontes/slugrunner-rb), [deis/slugrunner](https://github.com/deis/slugrunner), and the like.

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

```ruby
sb = Slugbuilder::Builder.new(repo: 'heroku/node-js-sample', git_ref: 'master')
sb.build // builds the slug `heroku.node-js-sample.master.tgz` in the current directory
```

### Builder#build

`build` builds the slug and writes build information to `STDOUT`.

- `repo` String (required): the github repo in the form `<organization>/<repository>`
- `git_ref` String (required): the SHA or branch to build
- `clear_cache` Boolean: destroys the cache before building when true
- `env` Hash: an optional hash of environment variables

## Configuration

Configuration settings can be modified within the `Slugbuilder.configure` block. Or set directly off of `Slugbuilder.config`

```ruby
Slugbuilder.configure do |config|
  config.base_dir = '/tmp/slugbuilder'
  config.cache_dir = '/tmp/slugbuilder-cache'
end

Slugbuilder.config.base_dir = '/tmp/slugbuilder'
Slugbuilder.config.cache_dir = '/tmp/slugbuilder-cache'
```

### Options
      @base_dir = '/tmp/slugbuilder'
      @cache_dir = '/tmp/slugbuilder-cache'
      @buildpack_dir = 'buildpacks'

**base_dir**

This is the base directory that builds and apps are stored in.

> Defaults to `/tmp/slugbuilder`

**cache_dir**

This is the directory where the cache lives.

> Defaults to `/tmp/slugbuilder-cache`

**buildpack_dir**

This is the directory where [buildpacks](https://devcenter.heroku.com/articles/buildpacks) live.

> Defaults to `buildpacks`

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
