version = "1.8.19"
author = "disruptek"
description = "a tiny tool to bump nimble versions"
license = "MIT"
requires "nim >= 1.0.0"
requires "cligen >= 0.9.40"
requires "https://github.com/disruptek/cutelog >= 1.1.2"

bin = @["bump"]

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c           -f -r " & test
  execCmd "nim c   -d:release -r " & test
  execCmd "nim c   -d:danger  -r " & test
  execCmd "nim cpp            -r " & test
  execCmd "nim cpp -d:danger  -r " & test
  when NimMajor >= 1 and NimMinor >= 1:
    execCmd "nim c   --gc:arc -r " & test
    execCmd "nim cpp --gc:arc -r " & test

task test, "run tests for travis":
  execTest("tests/tbump.nim")
