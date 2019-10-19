# bump

It just bumps your `.nimble` file versions, commits it, tags it, and pushes it.

## Usage
```
$ bump --help

# majors are for breaking changes
$ bump --major

# bump defaults to patch-level increments; you should add commit messages
$ bump fixed a bug

# you should add minors when you add functionality
$ bump --minor added a new feature

# you can specify a particular .nimble file to work on
$ bump --target some.nimble
$ bump --target some

# you can specify a particular package directory to look in
$ bump --directory /some/where/else

# a dry-run option merely shows you the future version/message
$ bump --dry-run fixed another bug
1.0.3: fixed another bug
```
