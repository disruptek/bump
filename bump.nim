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
  error why
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
      if target != "":
        if filename.extractFilename notin [target, target & ".nimble"]:
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

proc capture*(exe: string; args: seq[string]): tuple[output: string; ok: bool] =
  ## find and run a given executable with the given arguments;
  ## the result includes stdout and a true value if it seemed to work
  var
    command = findExe(exe)
  if command == "":
    result = (output: &"unable to find executable `{exe}` in path", ok: false)
    warn result.output
    return

  # we apparently need to escape arguments when using this subprocess form
  command &= " " & quoteShellCommand(args)
  debug command  # let's take a look at those juicy escape sequences

  # run it and get the output to construct our return value
  let (output, exit) = execCmdEx(command, {poEvalCommand, poDaemon})
  result = (output: output, ok: exit == 0)

  # provide a simplified summary at appropriate logging levels
  let
    ran = exe & " " & args.join(" ")
  if result.ok:
    info ran
  else:
    notice ran

proc run*(exe: string; args: varargs[string]): bool =
  ## find and run a given executable with the given arguments;
  ## the result is true if it seemed to work
  var
    arguments: seq[string]
  for n in args:
    arguments.add n
  result = capture(exe, arguments).ok

proc tagsAppearToStartWithV(): Option[bool] =
  ## try to determine if this project's git tags start with a `v`
  let
    caught = capture("git", @["tag", "--list"])
  if not caught.ok:
    return
  var
    splat = splitLines(caught.output, keepEol = false)
  # get rid of any empty trailing output
  while splat.len > 0 and splat[^1].strip == "":
    discard splat.pop
  if splat.len == 0:
    # if there's nothing left, let's assume there are no versions
    debug "no tags in `git tag --list`?  that makes it easy."
    result = false.some
  else:
    # we have a tag that, if lexical sort is to be believed, may
    # represent the latest tag added.  if it looks like it starts with
    # `v` and may be part of a version string, then yield truthiness!
    debug "the last tag in our `git tag --list` is", splat[^1]
    result = splat[^1].contains(re"^[vV]\.?\d").some
  debug &"my guess as to whether we use `v` tags: {result.get}"

proc bump*(minor = false; major = false; patch = true; release = false;
          dry_run = false; folder = "."; nimble = ""; log_level = logLevel;
          commit = false; v = false; message: seq[string]): int =
  ## the entry point from the cli
  var
    target: Target
    next: Version

  # user's choice, our default
  setLogFilter(log_level)

  # find the targeted .nimble file
  debug &"search `{folder}` for `{nimble}`"
  let
    found = findTarget(folder, target = nimble)
  if found.isNone:
    crash &"couldn't pick a .nimble from `{folder}/{nimble}`"
  else:
    debug "found", found.get
    target = found.get

  # make a temp file in an appropriate spot, with a significant name
  let
    temp = createTemporaryFile(target.package, ".nimble")
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
    for line in lines($target):
      if not line.contains(re"^version\s*="):
        writer.writeLine line
        continue

      # parse the current version number
      let
        last = line.parseVersion
      if last.isNone:
        crash &"unable to parse version from `{line}`"
      else:
        debug "current version is", last.get

      # bump the version number
      let
        bumped = last.get.bumpVersion(major, minor, patch)
      if bumped.isNone:
        crash "version unchanged; specify major, minor, or patch"
      else:
        debug "next version is", bumped.get
      next = bumped.get

      # make a subtle edit to the version string and write it out
      writer.writeLine next.withCrazySpaces(line)

  # move to the repo so we can do git operations
  debug "changing directory to", target.repo
  setCurrentDir(target.repo)

  # invent a tag and see if we should add a `v` prefix
  var tag = $next
  block veeville:
    if not v:
      let veeish = tagsAppearToStartWithV()
      if veeish.isNone:
        # like the sign says,
        warn "i can't tell if you want a v in front of your tags;"
        warn "some strange folks tag version `1.0.0` as `v1.0.0`."
        warn "i'll wait 10 seconds for you to interrupt, but after"
        warn "that, i'm gonna go ahead and assume you don't want `v`!"
        warn ""
        warn "(use the --v option to force a `v` on your tags)"
        sleep(10 * 1000)
        break veeville
      elif not veeish.get:
        break veeville
    tag = "v" & tag

  # make a git commit message
  var msg = tag
  if message.len > 0:
    msg &= ": " & message.join(" ")

  # cheer
  fatal &"🎉{msg}"

  if dry_run:
    debug "dry run and done"
    return

  # copy the new .nimble over the old one
  try:
    debug &"copying {temp} over", target
    copyFile(temp, $target)
  except Exception as e:
    discard e # noqa 😞
    crash &"failed to copy `{temp}` to `{target}`: {e.msg}"

  # move to the repo so we can do git operations
  debug "changing directory to", target.repo
  setCurrentDir(target.repo)

  # try to do some git operations
  block nimgitsfu:
    # commit just the .nimble file, or the whole repository
    var
      committee = if commit: target.repo else: $target
    if not run("git", "commit", "-m", msg, committee):
      break

    # if a message exists, omit the tag from the message
    if message.len > 0:
      msg = message.join(" ")

    # tag the commit with the new version
    if not run("git", "tag", "-a", "-m", msg, tag):
      break

    # push the commits
    if not run("git", "push"):
      break

    # push the tags
    if not run("git", "push", "--tags"):
      break

    # we might want to use hub to mark a github release
    if release:
      if not run("hub", "release", "create", "-m", msg, tag):
        break

    # celebrate
    fatal "🍻bumped"
    return 0

  # hang our head in shame
  fatal "🐼nimgitsfu fail"
  return 1

when isMainModule:
  import cligen

  let
    console = newConsoleLogger(levelThreshold = logLevel,
                               useStderr = true, fmtStr = "")
    logger = CuteLogger(forward: console)
  addHandler(logger)
  dispatch bump
