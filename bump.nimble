version = "1.8.24"
author = "disruptek"
description = "a tiny tool to bump nimble versions"
license = "MIT"

requires "https://github.com/disruptek/testes >= 0.7.1 & < 1.0.0"
requires "https://github.com/disruptek/cutelog >= 1.1.2 & < 2.0.0"

bin = @["bump"]

when (NimMajor, NimMinor) >= (1, 3):
  requires "cligen >= 1.2.2 & < 2.0.0"
else:
  requires "cligen >= 0.9.46 & < 2.0.0"

task test, "run tests for ci":
  when defined(windows):
    exec "testes.cmd"
  else:
    exec findExe"testes"
