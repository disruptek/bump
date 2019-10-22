# bump

It just bumps your `.nimble` file versions, commits it, tags it, and pushes it.

`hub` from https://github.com/github/hub enables GitHub-specific functionality.

## Usage
```
# bump defaults to patch-level increments; please add commit messages
$ bump fixed a bug
1.0.1: fixed a bug

# majors are for breaking changes
$ bump --major
2.0.0

# you should add minors when you add functionality
$ bump --minor added a new feature
2.1.0: added a new feature

# a dry-run option merely shows you the future version/message
$ bump --dry-run fixed another bug
2.1.1: fixed another bug

# you can use --v to specify a `v` prefix to your tags
$ bump --v only weirdos use v
v2.1.2: only weirdos use v

# you can commit the entire repo at once to consolidate commits
$ bump --commit quick fix for simple buglet
2.1.3: quick fix for simple buglet

# if you have `hub` installed, you can also mark a GitHub release
$ bump --minor --release add release option
2.2.0: add release option

# optionally set the Nim logging level for more spam
$ bump --log lvlDebug

# optionally specify a particular .nimble file to work on
$ bump --nimble some.nimble
$ bump --nimble some

# optionally specify a particular package directory to look in
$ bump --folder /some/where/else
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
