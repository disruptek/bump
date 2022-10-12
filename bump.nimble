version = "1.8.31"
author = "disruptek"
description = "a tiny tool to bump nimble versions"
license = "MIT"

requires "https://github.com/disruptek/cutelog >= 2.0.0 & < 3.0.0"
requires "https://github.com/disruptek/cligen >= 2.0.0 & < 3.0.0"
when not defined(release):
  requires "https://github.com/disruptek/balls >= 2.0.0 & < 4.0.0"

bin = @["bump"]

requires "https://github.com/disruptek/cligen < 3.0.0"

task test, "run tests for ci":
  when defined(windows):
    exec "balls.cmd"
  else:
    exec findExe"balls"
