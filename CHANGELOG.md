# Changelog

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
