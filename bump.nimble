version = "1.8.24"
author = "disruptek"
description = "a tiny tool to bump nimble versions"
license = "MIT"

requires "https://github.com/disruptek/cutelog >= 1.1.2 & < 2.0.0"

bin = @["bump"]

when (NimMajor, NimMinor) >= (1, 3):
  requires "cligen >= 1.2.2 & < 2.0.0"
else:
  requires "cligen >= 0.9.46 & < 2.0.0"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  when getEnv("GITHUB_ACTIONS", "false") != "true":
    execCmd "nim c -r " & test
    when (NimMajor, NimMinor) >= (1, 2):
      execCmd "nim cpp --gc:arc -d:danger -r " & test
  else:
    execCmd "nim c              -r " & test
    execCmd "nim cpp            -r " & test
    execCmd "nim c   -d:danger  -r " & test
    execCmd "nim cpp -d:danger  -r " & test
    when (NimMajor, NimMinor) >= (1, 2):
      execCmd "nim c --useVersion:1.0 -d:danger -r " & test
      execCmd "nim c   --gc:arc -d:danger -r " & test
      execCmd "nim cpp --gc:arc -d:danger -r " & test

task test, "run tests for ci":
  execTest("tests/tbump.nim")
