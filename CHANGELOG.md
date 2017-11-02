# Changelog

## 3.1.0 (2017-11-2)

Fixed:

- Avoid collisions on concurrent builds to the same repo. Each build now has its own environment and build output folder. [f3f36aa](../../commit/f3f36aa)

Improved:

- Scope cache to repo. This is more in line with how Heroku handles the cache and might help prevent bad caches. [21dc073](../../commit/21dc073)

## 3.0.0 (2017-7-12)

Changed:

  - Allow configuration of `STACK` environment variable. Now defaults to `heroku-16` instead of `cedar-14`. This is a potentially breaking change. [4ce8c61](../../commit/4ce8c61)

Added:

  - Improved error messaging from buildpacks. Rather than showing the stack trace from slugbuilder, show the data piped to stderr where the error occurred. [dbf5142](../../commit/dbf5142)

## 2.0.2 (2017-5-26)

Fixed:

- Move location of buildpack caching to prevent buildpacks that try to clear the entire cache directory from deleting themselves in the middle of running. [7e444e1](../../commit/7e444e1)

Added:

- Improved error messaging [209eead](../../commit/209eead)

## 2.0.1 (2017-5-25)

Fixed:

- Get force pushed changes from buildpack branches. [b976393](../../commit/b976393)

## 2.0.0 (2017-5-3)

Changed:

- Prebuild and postbuild hooks now take `git_url` as a keyword argument

Added:

- The `protocol` configuration option allows specifying the protocol to use when downloading git repositories
- Buildpack  and repository urls now accept more formats (`<organization>/<repository_name>`, `git@<git_service>:<organization>/<repository_name>.git`, and `https://<git_service>/<organization>/<repository_name>.git`

## 1.3.0 (2017-3-7)

Added:

- Run `bin/pre-compile` before any buildpacks are run (if it exists) and run `bin/post-compile` after all buildpacks are run (if it exists). These files are contained in the project being built. [e2b5295](../../commit/e2b5295)

## 1.2.0 (2017-2-1)

Fixed:

- Support multiple buildpacks such that they correctly pass environment variables to succeeding buildpacks [00c3010](../../commit/00c3010)
- Add support for buildpack compile's `ENV_DIR` argument. [06cbecd](../../commit/06cbecd)
- Handle errors on git commands [051e281](../../commit/051e281)
- Run buildpacks without context of preexisting environment [d5767e8](../../commit/d5767e8)

Added:

- Show error backtrace [21cfc90](../../commit/21cfc90)
- Set `REQUEST_ID` and `SOURCE_VERSION` environment variables [c8834c1](../../commit/c8834c1) and [8804f50](../../commit/8804f50)

## 1.1.0 (2017-1-27)

Fixed:

- `build` with `clear_cache: true` now works correctly [e535c96](../../commit/e535c96)

Added:

- `build` optionally takes a `buildpacks` keyword argument that specifies an array of buildpacks to use for that particular build [3871ff9](../../commit/3871ff9)

## 1.0.0 (2017-1-18)

Initial release
