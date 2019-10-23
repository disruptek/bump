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
  debug &"find target input `{dir}` and `{target}`"
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

proc withCrazySpaces*(version: Version; line = ""): string =
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

proc appearsToBeMasterBranch*(): Option[bool] =
  ## try to determine if we're on the `master` branch
  let
    caught = capture("git", @["branch", "--show-current"])
  if not caught.ok:
    return
  result = caught.output.contains(re"(*ANYCRLF)(?m)(?x)^master$").some
  debug &"appears to be master branch? {result.get}"

proc fetchTagList*(): Option[string] =
  ## simply retrieve the tags as a string; attempt to use the
  ## later git option to sort the result by version
  var
    caught = capture("git", @["tag", "--sort=version:refname"])
  if not caught.ok:
    caught = capture("git", @["tag", "--list"])
  if not caught.ok:
    return
  result = caught.output.strip.some

proc lastTagInTheList*(tagList: string): string =
  ## lazy way to get a tag from the list, whatfer mimicking its V form
  let
    verex = re("(*ANYCRLF)(?i)(?m)^v?\\.?\\d+\\.\\d+\\.\\d+$")
  for match in tagList.findAll(verex):
    result = match
  if result == "":
    raise newException(ValueError, "could not identify a sane tag")
  debug &"the last tag in the list is `{result}`"

proc taggedAs*(version: Version; tagList: string): Option[string] =
  ## try to fetch a tag that appears to match a given version
  let
    escaped = replace($version, ".", "\\.")
    verex = re("(*ANYCRLF)(?i)(?m)^v?\\.?" & escaped & "$")
  for match in tagList.findAll(verex):
    if result.isSome:
      debug &"got more than one tag for version {version}:"
      debug &"`{result.get}` and `{match}`"
      result = none(string)
      break
    result = match.some
  if result.isSome:
    debug &"version {version} was tagged as {result.get}"

proc allTagsAppearToStartWithV*(tagList: string): bool =
  ## try to determine if all of this project's tags start with a `v`
  let
    splat = tagList.splitLines(keepEol = false)
    verex = re("(?i)(?x)^v\\.?\\d+\\.\\d+\\.\\d+$")
  # if no tags exist, the result is false, right?  RIGHT?
  if splat.len == 0:
    return
  for line in splat:
    if not line.contains(verex):
      debug &"found a tag `{line}` which doesn't use `v`"
      return
  result = true
  debug &"all tags appear to start with `v`"

proc shouldSearch(folder: string; nimble: string):
  Option[tuple[dir: string; file: string]] =
  ## given a folder and nimble file (which may be empty), find the most useful
  ## directory and target filename to search for. this is a little convoluted
  ## because we're trying to perform the function of three options in one proc.
  var
    dir, file: string
  if folder == "":
    if nimble != "":
      # there's no folder specified, so if a nimble was provided,
      # split it into a directory and file for the purposes of search
      (dir, file) = splitPath(nimble)
    # if the directory portion is empty, search the current directory
    if dir == "":
      dir = "."
  else:
    dir = folder
    file = nimble
  # by now, we at least know where we're gonna be looking
  if not existsDir(dir):
    warn &"`{dir}` is not a directory"
    return
  # try to look for a .nimble file just in case
  # we can identify it quickly and easily here
  while file != "" and not existsFile(dir / file):
    if file.endsWith(".nimble"):
      # a file was specified but we cannot find it, even given
      # a reasonable directory and the addition of .nimble
      warn &"`{dir}/{file}` does not exist"
      return
    file &= ".nimble"
  debug &"should search `{dir}` for `{file}`"
  result = (dir: dir, file: file).some

proc pluckVAndDot(input: string): string =
  ## return any `V` or `v` prefix, perhaps with an existing `.`
  if input[0] notin {'V', 'v'}:
    result = ""
  elif input[1] == '.':
    result = input[0 .. 1]
  else:
    result = input[0 .. 0]

proc composeTag*(last: Version; next: Version; v = false; tags = ""):
  Option[string] =
  ## invent a tag given last and next version, magically adding any
  ## needed `v` prefix.  fetches tags if a tag list isn't supplied.
  var
    tag, list: string

  # get the list of tags as a string; boy, i love strings
  if tags != "":
    list = tags
  else:
    let
      tagList = fetchTagList()
    if tagList.isNone:
      error &"unable to retrieve tags"
      return
    list = tagList.get

  let
    veeish = allTagsAppearToStartWithV(list)
    lastTag = last.taggedAs(list)

  # first, see what the last version was tagged as
  if lastTag.isSome:
    if lastTag.get.toLowerAscii.startsWith("v"):
      # if it starts with `v`, then use `v` similarly
      tag = lastTag.get.pluckVAndDot & $next
    elif v:
      # it didn't start with `v`, but the user wants `v`
      tag = "v" & $next
    else:
      # it didn't start with `v`, so neither should this tag
      tag = $next
  # otherwise, see if all the prior tags use `v`
  elif veeish:
    # if all the tags start with `v`, it's a safe bet that we want `v`
    # pick the last tag and match its `v` syntax
    tag = lastTagInTheList(list).pluckVAndDot & $next
  # no history to speak of, but the user asked for `v`; give them `v`
  elif v:
    tag = "v" & $next
  # no history, didn't ask for `v`, so please just don't use `v`!
  else:
    tag = $next
  result = tag.some
  debug &"composed the tag `{result.get}`"

proc bump*(minor = false; major = false; patch = true; release = false;
          dry_run = false; folder = ""; nimble = ""; log_level = logLevel;
          commit = false; v = false; message: seq[string]): int =
  ## the entry point from the cli
  var
    target: Target
    next: Version
    last: Option[Version]

  # user's choice, our default
  setLogFilter(log_level)

  if folder != "":
    warn "the --folder option is deprecated; please use --nimble instead"

  # take a stab at whether our .nimble file search might be illegitimate
  let search = shouldSearch(folder, nimble)
  if search.isNone:
    # uh oh; it's not even worth attempting a search
    crash &"nothing to bump"
  # find the targeted .nimble file
  let
    found = findTarget(search.get.dir, target = search.get.file)
  if found.isNone:
    crash &"couldn't pick a .nimble from `{search.get.dir}/{search.get.file}`"
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

  # compose a new tag
  let
    composed = composeTag(last.get, next, v = v)
  if composed.isNone:
    crash "i can't safely guess at enabling `v`; try a manual tag first?"
  let
    tag = composed.get

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

    # tag the commit with the new version and message
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
