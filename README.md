# bump

It just bumps your `.nimble` file versions, commits it, tags it, and pushes it.

`hub` from https://github.com/github/hub enables GitHub-specific functionality.

## Usage
```
# start here
$ bump --help

# majors are for breaking changes
$ bump --major
2.0.0

# bump defaults to patch-level increments; please add commit messages
$ bump fixed a bug
2.0.1: fixed a bug

# you should add minors when you add functionality
$ bump --minor added a new feature
2.1.0: added a new feature

# a dry-run option merely shows you the future version/message
$ bump --dry-run fixed another bug
2.1.1: fixed another bug

# you can use --v to specify a `v` prefix to your tags
$ bump --v only weirdos use v
v2.1.2: only weirdos use v

# if you have `hub` installed, you can also mark a GitHub release
$ bump --minor --release add release option
2.2.0: add release option

# optionally set the Nim logging level for more spam
$ bump --log lvlDebug

# optionally specify a particular .nimble file to work on
$ bump --target some.nimble
$ bump --target some

# optionally specify a particular package directory to look in
$ bump --directory /some/where/else
```

## License
MIT
