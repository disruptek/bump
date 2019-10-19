import os
import options
import osproc
import strutils
import strformat
import nre
import logging

import cligen

type
  Version = tuple[major: int; minor: int; patch: int]

proc findOneNimble*(dir: string; target = ""): Option[string] =
  block found:
    for component, filename in walkDir("."):
      if not filename.endsWith(".nimble") or component != pcFile:
        continue
      if target != "" and filename notin [target, target & ".nimble"]:
        continue
      if result.isSome:
        error "many .nimble files in `{dir}`: `{result.get}` and `{filename}`"
        break found
      result = some(filename)
    return
  result = none(string)

proc createTemporaryFile*(prefix: string; suffix: string): string =
  ## it should create the file, but so far, it doesn't
  let temp = getTempDir()
  result = temp / "bump-" & $getCurrentProcessId() & prefix & suffix

proc parseVersion(line: string): Version =
  let
    verex = line.match re(r"""^version = "(\d+).(\d+).(\d+)"""")
  if not verex.isSome:
    error "unable to parse version"
  let cap = verex.get.captures.toSeq
  result = (major: cap[0].get.parseInt,
            minor: cap[1].get.parseInt,
            patch: cap[2].get.parseInt)

proc bumpVersion(ver: Version; major, minor, patch: bool = false): Version =
  if major:
    result = (ver.major + 1, 0, 0)
  elif minor:
    result = (ver.major, ver.minor + 1, 0)
  elif patch:
    result = (ver.major, ver.minor, ver.patch + 1)

proc `$`(ver: Version): string =
  result = &"{ver.major}.{ver.minor}.{ver.patch}"

proc gitOkay(args: varargs[string, `$`]): bool =
  let
    git = findExe("git")
  var
    process: Process
    arguments: seq[string]
  for n in args:
    arguments.add n
  process = startProcess(git, args = arguments, options = {})
  result = process.waitForExit == 0
  if not result:
    error &"command-line failed:\n{git} " & arguments.join(" ")

proc bump(major: bool = false; minor: bool = false; patch: bool = true;
          directory = "."; target = ""; message: seq[string]) =
  var
    nimble: string
    repo: string
    past, next: Version

  # find git and the targetted .nimble file
  let
    found = findOneNimble(directory, target = target)
  if found.isNone:
    return
  else:
    nimble = found.get
    repo = parentDir(nimble)

  # make a temp file and rewrite it
  let
    temp = createTemporaryFile("", ".nimble")
  var writer = temp.open(fmWrite)
  for line in nimble.lines:
    if not line.startsWith("version = "):
      writer.writeLine line
      continue

    # bump the version number
    past = line.parseVersion
    next = past.bumpVersion(major, minor, patch)
    writer.writeLine &"""version = "{next}""""
  writer.close

  assert next.major == 0
  assert next.minor == 0
  assert next.patch == 2

  # write the new nimble over the old one and remove the temp file
  try:
    copyFile(temp, nimble)
  except Exception as e:
    echo e.msg
  if not tryRemoveFile(temp):
    quit "unable to remove temporary file `{temp}`"

  # make a git commit message
  var
    msg = $next
  if message.len > 0:
    msg &= ": " & message.join(" ")

  # move to the repo so we can do git operations
  setCurrentDir(repo)

  # try to do some git operations
  while true:
    # commit the nimble file
    if not gitOkay("commit", "-m", msg, nimble):
      break

    # tag the release
    if not gitOkay("tag", "-a", "-m", msg, $next):
      break

    # push the commit
    if not gitOkay("push"):
      break

    # push the tag
    if not gitOkay("push", "--tags"):
      break

    # we're done
    echo "bumped to " & $next
    quit(0)

  # we failed at our nimgitsfu
  quit(1)

when isMainModule:
  import cligen
  import logging

  when defined(release) or defined(danger):
    let level = lvlWarn
  else:
    let level = lvlAll
  let logger = newConsoleLogger(useStderr=true, levelThreshold=level)
  addHandler(logger)

  dispatch bump
