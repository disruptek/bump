# bump

[![Test Matrix](https://github.com/disruptek/bump/workflows/CI/badge.svg)](https://github.com/disruptek/bump/actions?query=workflow%3ACI)
[![GitHub release (latest by date)](https://img.shields.io/github/v/release/disruptek/bump?style=flat)](https://github.com/disruptek/bump/releases/latest)
![Minimum supported Nim version](https://img.shields.io/badge/nim-1.6.11%2B-informational?style=flat&logo=nim)
[![License](https://img.shields.io/github/license/disruptek/bump?style=flat)](#license)

It just **bumps** the value of the `version` in your `.nimble` file, commits it, tags it, and pushes it.

`hub` from https://github.com/github/hub enables GitHub-specific functionality.

For an explanation of the "social contract" that is semantic versioning, see https://semver.org/

**Note:** I only test bump on Linux against `git v2.23.0`, but it seems to work against `git v2.17.0`.  It has also been tested on OS X with `git v2.23.0`.  Platform-specific code in the tool:

1. we identify your current working directory differently on `macos` and `genode`, and perhaps some day, other platforms as well.

1. by the same token (well, not the **same** token, but...) if Nim ever invents a new `ExtSep` for your platform (ie. the character that separates filename from its extension), you can rebuild bump to use that new separator.

If you had to read that section carefully, please file a bug report with your vendor.

## Usage

By default, bump increments the patch number. You can also select the
field explicitly with `--patch`, which has parity with `--minor`
and `--major`.
```
$ bump
🎉1.0.1
🍻bumped
```

You can set the Nim logging level to monitor progress or check assumptions.
If built with `-d:debug`, you'll get `lvlDebug` output by default. Release
builds default to `lvlNotice`, and the default log-level is set to `lvlInfo`
otherwise.

```
$ bump --log lvlInfo
✔️git tag --list
🎉1.0.2
✔️git commit -m 1.0.2 /some/demo.nimble
✔️git tag -a -m 1.0.2 1.0.2
✔️git push
✔️git push --tags
🍻bumped
```

Please add a few words to describe the reason for the new version. These will
show up in tags as well.
```
$ bump fixed a bug
🎉1.0.3: fixed a bug
🍻bumped
```

Major bumps are for changes that might disrupt another user of the software.
```
$ bump --major api redesign
🎉2.0.0: api redesign
🍻bumped
```

You should add minors when you add functionality.
```
$ bump --minor added a new feature
🎉2.1.0: added a new feature
🍻bumped
```

A dry-run option merely shows you the future version/message.
```
$ bump --dry-run what if i fix another bug?
🎉2.1.1: what if i fix another bug?
$ bump fixed another bug!
🎉2.1.1: fixed another bug!
🍻bumped
```

You can specify the next version manually if necessary.
```
$ bump --manual 3.3.1 wrapper tracks version from upstream lib
🎉3.3.1: wrapper tracks version from upstream lib
🍻bumped
```

If you already use a `v` prefix for your tags, bump will add one, too.
```
$ bump strange tag ahead
🎉v2.1.2: strange tag ahead
🍻bumped
```

You can use `--v` to force the `v` prefix. This is might be necessary if you
want a `v` prefix and you haven't created any tags yet, or if you have other
atypical tags in `git tag --list`.
```
$ bump --v my first tag is a weird one
🎉v1.0.1: my first tag is a weird one
🍻bumped
```

If your last version had a `[vV]\.?` prefix, your next one will, too.
```
$ git tag -m 'a very bad idea' -a V.1.0.2
$ bump going from bad to worse
🎉V.1.0.3: going from bad to worse
🍻bumped
```

You can commit the entire repository at once to reduce gratuitous commits.
```
$ bump --commit quick fix for simple buglet
🎉2.1.4: quick fix for simple buglet
🍻bumped
```

If you have `hub` installed, you can also mate a GitHub release to the new tag.
```
$ bump --minor --release add release option
🎉2.2.0: add release option
🍻bumped
```

Optionally specify a particular `.nimble` file to work on.
```
$ bump --nimble other.nimble
🎉2.6.10
🍻bumped
```

## Complete Options via `--help`
```
Usage:
  bump [optional-params] [message: string...]
increment the version of a nimble package, tag it, and push it via git
Options(opt-arg sep :|=|spc):
  -h, --help                          print this cligen-erated help
  --help-syntax                       advanced: prepend,plurals,..
  -m, --minor        bool    false    increment the minor version field
  --major            bool    false    increment the major version field
  -p, --patch        bool    false    increment the patch version field
  -r, --release      bool    false    also use `hub` to issue a GitHub release
  -d, --dry-run      bool    false    just report the projected version
  -f=, --folder=     string  ""       specify the location of the nimble file
  -n=, --nimble=     string  ""       specify the nimble file to modify
  -l=, --log-level=  Level   lvlInfo  specify Nim logging level
  -c, --commit       bool    false    also commit any other unstaged changes
  -v, --v            bool    false    prefix the version tag with an ugly `v`
  --manual=          string  ""       manually set the new version to #.#.#
```

## Library Use
There are some procedures exported for your benefit; see [the documentation for the module as generated directly from the source](https://disruptek.github.io/bump/bump.html).

## License
MIT
