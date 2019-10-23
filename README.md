# bump

It just **bumps** the value of the `version` in your `.nimble` file, commits it, tags it, and pushes it.

`hub` from https://github.com/github/hub enables GitHub-specific functionality.

For an explanation of the "social contract" that is semantic versioning, see https://semver.org/

## Usage

By default, bump increments the patch number.
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
$ bump --nimble some
🎉2.6.11
🍻bumped
```

Optionally specify a particular package directory to look in.
```
$ bump --folder /some/where/else
🎉1.4.31
🍻bumped
```

## Complete Options via `--help`
```
Usage:
  bump [optional-params] [message: string...]
the entry point from the cli
Options(opt-arg sep :|=|spc):
  -h, --help                           print this cligen-erated help
  --help-syntax                        advanced: prepend,plurals,..
  -m, --minor        bool    false     set minor
  --major            bool    false     set major
  -p, --patch        bool    true      set patch
  -r, --release      bool    false     set release
  -d, --dry-run      bool    false     set dry_run
  -f=, --folder=     string  "."       set folder
  -n=, --nimble=     string  ""        set nimble
  -l=, --log-level=  Level   lvlDebug  set log_level
  -c, --commit       bool    false     set commit
  -v, --v            bool    false     set v
```

## License
MIT
