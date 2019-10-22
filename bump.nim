import os
import options
import osproc
import strutils
import strformat
import nre
import logging


type
  Version* = tuple[major: int; minor: int; patch: int]
  Target* = tuple[repo: string; package: string; ext: string]
  CuteLogger = ref object of Logger
    forward: Logger

when defined(debug):
  const logLevel = lvlDebug
elif defined(release) or defined(danger):
  const logLevel = lvlNotice
else:
  const logLevel = lvlInfo

method log(logger: CuteLogger; level: Level; args: varargs[string, `$`])
  {.locks: "unknown", raises: [].} =
  ## anything that isn't fatal gets a cute emoji
  var
    prefix: string
    arguments: seq[string]
  for a in args:
    arguments.add a
  case level:
  of lvlFatal:   # use this level for our most critical outputs
    prefix = ""  # and don't prefix them with a glyph
  of lvlError:
    prefix = "💥"
  of lvlWarn:
    prefix = "⚠️"
  of lvlNotice:
    prefix = "❌"
  of lvlInfo:
    prefix = "✔️"
  of lvlDebug:
    prefix = "🐛"
  of lvlAll, lvlNone:  # fwiw, this method is never called with these
    discard
  try:
    logger.forward.log(level, prefix & arguments.join(" "))
  except:
    discard

template crash(why: string) =
  ## a good way to exit bump()
  fatal why
  return 1

proc `$`*(target: Target): string =
  result = target.repo / target.package & target.ext

proc `$`*(ver: Version): string =
  result = &"{ver.major}.{ver.minor}.{ver.patch}"

proc findTarget*(dir: string; target = ""): Option[Target] =
  ## locate one, and only one, nimble file to work upon;
  ## dir is where to look, target is a .nimble or package name
  block found:
    for component, filename in walkDir(dir):
      if not filename.endsWith(".nimble") or component != pcFile:
        continue
      if target != "" and filename notin [target, target & ".nimble"]:
        continue
      if result.isSome:
        warn &"found `{result.get}` and `{filename}` in `{dir}`"
        break found
      let splat = filename.absolutePath.splitFile
      result = (repo: splat.dir, package: splat.name, ext: splat.ext).some
    # we set result only once, so this is a some(Target) return
    return
  result = none(Target)

proc createTemporaryFile*(prefix: string; suffix: string): string =
  ## it should create the file, but so far, it doesn't
  let temp = getTempDir()
  result = temp / "bump-" & $getCurrentProcessId() & "-" & prefix & suffix

proc parseVersion*(line: string): Option[Version] =
  ## parse a version specifier line from the .nimble file
  let
    verex = line.match re(r"""^version\s*=\s*"(\d+).(\d+).(\d+)"""")
  if not verex.isSome:
    return
  let cap = verex.get.captures.toSeq
  result = (major: cap[0].get.parseInt,
            minor: cap[1].get.parseInt,
            patch: cap[2].get.parseInt).some

proc bumpVersion*(ver: Version; major, minor, patch = false): Option[Version] =
  ## increment the version by the specified metric
  if major:
    result = (ver.major + 1, 0, 0).some
  elif minor:
    result = (ver.major, ver.minor + 1, 0).some
  elif patch:
    result = (ver.major, ver.minor, ver.patch + 1).some

proc withCrazySpaces(version: Version; line = ""): string =
  ## insert a new version into a line which may have "crazy spaces"
  while line != "":
    let
      verex = line.match re(r"""^version(\s*)=(\s*)"\d+.\d+.\d+"(\s*)""")
    if not verex.isSome:
      break
    let
      cap = verex.get.captures.toSeq
      (c1, c2, c3) = (cap[0].get, cap[1].get, cap[2].get)
    result = &"""version{c1}={c2}"{version}"{c3}"""
    return
  result = &"""version = "{version}""""

proc run*(exe: string; args: varargs[string, `$`]): bool =
  ## find and run a given executable with the given arguments;
  ## the result is true if it seemed to work
  let
    path = findExe(exe)
  if path == "":
    warn &"unable to find executable `{exe}` in path"
    return false

  var
    process: Process
    arguments: seq[string]
  for n in args:
    arguments.add n
  let
    ran = exe & " " & arguments.join(" ")
  debug path, arguments.join(" ")
  process = path.startProcess(args = arguments, options = {})
  result = process.waitForExit == 0
  if result:
    info ran
  else:
    notice ran

proc bump*(minor = false; major = false; patch = true; release = false;
          dry_run = false; directory = "."; target = ""; log_level = logLevel;
          message: seq[string]): int =
  ## the entry point from the cli
  var
    nimble: Target
    next: Version

  # user's choice, our default
  setLogFilter(log_level)

  # find the targeted .nimble file
  debug &"search `{directory}` for `{target}`"
  let
    found = findTarget(directory, target = target)
  if found.isNone:
    crash &"couldn't pick a .nimble from dir `{directory}` & target `{target}`"
  else:
    debug "found", found.get
    nimble = found.get

  # make a temp file in an appropriate spot, with a significant name
  let
    temp = createTemporaryFile(nimble.package, ".nimble")
  debug &"writing {temp}"
  # but remember to remove the temp file later
  defer:
    debug &"removing {temp}"
    if not tryRemoveFile(temp):
      warn &"unable to remove temporary file `{temp}`"

  block writing:
    # open our temp file for writing
    var
      writer = temp.open(fmWrite)
    # but remember to close the temp file in any event
    defer:
      writer.close
    for line in lines($nimble):
      if not line.contains(re"^version\s*="):
        writer.writeLine line
        continue

      # bump the version number
      let
        last = line.parseVersion
      if last.isNone:
        crash &"unable to parse version from `{line}`"
      else:
        debug "current version is", last.get
      let
        bumped = last.get.bumpVersion(major, minor, patch)
      if bumped.isNone:
        crash "version unchanged; specify major, minor, or patch"
      else:
        debug "next version is", bumped.get
      next = bumped.get
      writer.writeLine next.withCrazySpaces(line)

  # make a git commit message
  var
    msg = $next
  if message.len > 0:
    msg &= ": " & message.join(" ")
  fatal &"🎉{msg}"

  if dry_run:
    debug "dry run and done"
    return

  # copy the new .nimble over the old one
  try:
    debug &"copying {temp} over", nimble
    copyFile(temp, $nimble)
  except Exception as e:
    discard e # noqa 😞
    crash &"failed to copy `{temp}` to `{nimble}`: {e.msg}"

  # move to the repo so we can do git operations
  debug "changing directory to", nimble.repo
  setCurrentDir(nimble.repo)

  # try to do some git operations
  while true:
    # commit the nimble file
    if not run("git", "commit", "-m", msg, nimble):
      break

    # if a message exists, omit the version from the tag
    if message.len > 0:
      msg = message.join(" ")

    # tag the commit with the new version
    if not run("git", "tag", "-a", "-m", msg, next):
      break

    # push the commit
    if not run("git", "push"):
      break

    # push the tag
    if not run("git", "push", "--tags"):
      break

    # we might want to use hub to mark a github release
    if release:
      if not run("hub", "release", "create", "-m", msg, next):
        break

    # we're done
    fatal "🍻bumped"
    return

  error "nimgitsfu fail"
  return 1

when isMainModule:
  import cligen

  let
    console = newConsoleLogger(levelThreshold = logLevel,
                               useStderr = true, fmtStr = "")
    logger = CuteLogger(forward: console)
  addHandler(logger)
  dispatch bump
