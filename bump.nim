import std/os
import std/options
import std/osproc
import std/strutils
import std/strformat
import std/nre

from std/macros import nil

import cutelog

type
  Version* = tuple
    major: uint
    minor: uint
    patch: uint

  Target* = tuple
    repo: string
    package: string
    ext: string

  SearchResult* = tuple
    message: string
    found: Option[Target]

const
  dotNimble = "".addFileExt("nimble")
  defaultExts = @["nimble"]
  logLevel =
    when defined(debug):
      lvlDebug
    elif defined(release):
      lvlNotice
    elif defined(danger):
      lvlNotice
    else:
      lvlInfo

template crash(why: string) =
  ## a good way to exit bump()
  error why
  return 1

proc `$`*(target: Target): string =
  result = target.repo / target.package & target.ext

proc `$`*(ver: Version): string =
  result = &"{ver.major}.{ver.minor}.{ver.patch}"

proc relativeParentPath*(dir: string): string =
  ## the parent directory as expressed relative to the directory supplied
  result = dir / ParDir

proc isFilesystemRoot*(dir: string): bool =
  ## true if there are no higher directories in the fs tree
  result = sameFile(dir, dir.relativeParentPath)

proc isNamedLikeDotNimble(dir: string; file: string): bool =
  ## true if it the .nimble filename (minus ext) matches the directory
  if dir == "" or file == "":
    return
  if not file.endsWith(dotNimble):
    return
  result = dir.lastPathPart == file.changeFileExt("")

proc safeCurrentDir(): string =
  when nimvm:
    result = os.getEnv("PWD", os.getEnv("CD", ""))
  else:
    result = getCurrentDir()

proc newTarget*(path: string): Target =
  let splat = path.splitFile
  result = (repo: splat.dir, package: splat.name, ext: splat.ext)

proc findTargetWith(dir: string; cwd: proc (): string; target = "";
                    ascend = true; extensions = defaultExts): SearchResult =
  ## locate one, and only one, nimble file to work upon; dir is where
  ## to start looking, target is a .nimble or package name

  # viable selections are limited to the target and possible extensions
  var
    viable: seq[string]
    exts: seq[string]

  # an empty extension is acceptable in the extensions argument
  for extension in extensions.items:
    # create mypackage.nimble, mypackage.nimble-link
    viable.add target.addFileExt(extension)

    # create .nimble, .nimble-link
    exts.add "".addFileExt(extension)

  # search the directory for a .nimble file
  for component, filename in walkDir(dir):
    if component notin {pcFile, pcLinkToFile}:
      continue
    let splat = splitFile(filename)

    # first, look at the whole filename for the purposes of matching
    if target != "":
      if filename.extractFilename notin viable:
        continue
    # otherwise, fall back to checking for suitable extension
    elif splat.ext notin exts:
      continue

    # a 2nd .nimble overrides the first if it matches the directory name
    if result.found.isSome:
      # if it also isn't clearly the project's .nimble, keep looking
      if not isNamedLikeDotNimble(dir, filename):
        result = (message:
                    &"found `{result.found.get}` and `{filename}` in `{dir}`",
                  found: none(Target))
        continue

    # we found a .nimble; let's set our result and keep looking for a 2nd
    result = (message: &"found target in `{dir}` given `{target}`",
              found: newTarget(filename).some)

    # this appears to be the best .nimble; let's stop looking here
    if isNamedLikeDotNimble(dir, filename):
      break

  # we might be good to go, here
  if result.found.isSome or not ascend:
    return

  # otherwise, maybe we can recurse up the directory tree.
  # if our dir is `.`, then we might want to shadow it with a
  # full current dir using the supplied proc

  let dir = if dir == ".": cwd() else: dir

  # if we're already at a root, i guess we're done
  if dir.isRootDir:
    return (message: "", found: none(Target))

  # else let's see if we have better luck in a parent directory
  var
    refined = findTargetWith(dir.parentDir, cwd, target = target)

  # return the refinement if it was successful,
  if refined.found.isSome:
    return refined

  # or if the refinement yields a superior error message
  if refined.message != "" and result.message == "":
    return refined

proc findTarget*(dir: string; target = ""): SearchResult =
  ## locate one, and only one, nimble file to work upon; dir is where
  ## to start looking, target is a .nimble or package name
  result = findTargetWith(dir, safeCurrentDir, target = target)

proc findTarget*(dir: string; target = ""; ascend = true;
                 extensions: seq[string]): SearchResult =
  ## locate one, and only one, nimble file to work upon; dir is where
  ## to start looking, target is a .nimble or package name,
  ## extensions list optional extensions (such as "nimble")
  result = findTargetWith(dir, safeCurrentDir, target = target,
                          ascend = ascend, extensions = extensions)

proc createTemporaryFile*(prefix: string; suffix: string): string =
  ## it SHOULD create the file, but so far, it only returns the filename
  let temp = getTempDir()
  result = temp / "bump-" & $getCurrentProcessId() & "-" & prefix & suffix

proc isValid*(ver: Version): bool =
  ## true if the version seems legit
  result = ver.major > 0'u or ver.minor > 0'u or ver.patch > 0'u

proc parseVersion*(nimble: string): Option[Version] =
  ## try to parse a version from any line in a .nimble;
  ## safe to use at compile-time
  for line in nimble.splitLines:
    if not line.startsWith("version"):
      continue
    let
      fields = line.split('=')
    if fields.len != 2:
      continue
    var
      dotted = fields[1].replace("\"").strip.split('.')
    case dotted.len:
    of 3: discard
    of 2: dotted.add "0"
    else:
      continue
    try:
      result = (major: dotted[0].parseUInt,
                minor: dotted[1].parseUInt,
                patch: dotted[2].parseUInt).some
    except ValueError:
      discard

proc bumpVersion*(ver: Version; major, minor, patch = false): Option[Version] =
  ## increment the version by the specified metric
  if major:
    result = (ver.major + 1'u, 0'u, 0'u).some
  elif minor:
    result = (ver.major, ver.minor + 1'u, 0'u).some
  elif patch:
    result = (ver.major, ver.minor, ver.patch + 1'u).some

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

proc capture*(exe: string; args: seq[string];
              options: set[ProcessOption]): tuple[output: string; ok: bool] =
  ## capture output of a command+args and indicate apparent success
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
  let (output, exit) = execCmdEx(command, options)
  result = (output: output, ok: exit == 0)

  # provide a simplified summary at appropriate logging levels
  let
    ran = exe & " " & args.join(" ")
  if result.ok:
    info ran
  else:
    notice ran

proc capture*(exe: string; args: seq[string]): tuple[output: string; ok: bool] =
  ## find and run a given executable with the given arguments;
  ## the result includes stdout/stderr and a true value if it seemed to work
  result = capture(exe, args, {poStdErrToStdOut, poDaemon, poEvalCommand})

proc run*(exe: string; args: varargs[string]): bool =
  ## find and run a given executable with the given arguments;
  ## the result is true if it seemed to work
  var
    arguments: seq[string]
  for n in args:
    arguments.add n
  let
    caught = capture(exe, arguments)
  if not caught.ok:
    notice caught.output
  result = caught.ok

proc appearsToBeMasterBranch*(): Option[bool] =
  ## try to determine if we're on the `master`/`main` branch
  var
    caught = capture("git", @["branch", "--show-current"])
  if caught.ok:
    result = caught.output.contains(re"(*ANYCRLF)(?m)(?x)^master|main$").some
  else:
    caught = capture("git", @["branch"])
    if not caught.ok:
      notice caught.output
      return
    result = caught.output.contains(re"(*ANYCRLF)(?m)(?x)^master|main$").some
  debug &"appears to be master/main branch? {result.get}"

proc fetchTagList*(): Option[string] =
  ## simply retrieve the tags as a string; attempt to use the
  ## later git option to sort the result by version
  var
    caught = capture("git", @["tag", "--sort=version:refname"])
  if not caught.ok:
    caught = capture("git", @["tag", "--list"])
  if not caught.ok:
    notice caught.output
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
  ## because we're trying to replace the function of three options in one proc.
  var
    dir, file: string
  if folder == "":
    if nimble != "":
      # there's no folder specified, so if a nimble was provided,
      # split it into a directory and file for the purposes of search
      (dir, file) = splitPath(nimble)
    # if the directory portion is empty, search the current directory
    if dir == "":
      dir = $CurDir  # should be correct regardless of os
  else:
    dir = folder
    file = nimble
  # by now, we at least know where we're gonna be looking
  if not dirExists(dir):
    warn &"`{dir}` is not a directory"
    return
  # try to look for a .nimble file just in case
  # we can identify it quickly and easily here
  while file != "" and not fileExists(dir / file):
    if file.endsWith(dotNimble):
      # a file was specified but we cannot find it, even given
      # a reasonable directory and the addition of .nimble
      warn &"`{dir}/{file}` does not exist"
      return
    file &= dotNimble
  debug &"should search `{dir}` for `{file}`"
  result = (dir: dir, file: file).some

proc pluckVAndDot*(input: string): string =
  ## return any `V` or `v` prefix, perhaps with an existing `.`
  if input.len == 0 or input[0] notin {'V', 'v'}:
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
          commit = false; v = false; manual = ""; message: seq[string]): int =
  ## the entry point from the cli
  var
    target: Target
    next: Version
    last: Option[Version]

  # user's choice, our default
  setLogFilter(log_level)

  if folder != "":
    warn "the --folder option is deprecated; please use --nimble instead"

  # parse and assign a version number manually provided by the user
  if manual != "":
    # use our existing parser for consistency
    let future = parseVersion(&"""version = "{manual}"""")
    if future.isNone or not future.get.isValid:
      crash &"unable to parse supplied version `{manual}`"
    next = future.get
    debug &"user-specified next version as `{next}`"

  # take a stab at whether our .nimble file search might be illegitimate
  let search = shouldSearch(folder, nimble)
  if search.isNone:
    # uh oh; it's not even worth attempting a search
    crash &"nothing to bump"
  # find the targeted .nimble file
  let
    sought = findTarget(search.get.dir, target = search.get.file)
  if sought.found.isNone:
    # emit any available excuse as to why we couldn't find .nimble
    if sought.message != "":
      warn sought.message
    crash &"couldn't pick a {dotNimble} from `{search.get.dir}/{search.get.file}`"
  else:
    debug sought.message
    target = sought.found.get

  # if we're not on the master/main branch, let's just bail for now
  let
    branch = appearsToBeMasterBranch()
  if branch.isNone:
    crash "uh oh; i cannot tell if i'm on the master/main branch"
  elif not branch.get:
    crash "i'm afraid to modify any branch that isn't master/main"
  else:
    debug "good; this appears to be the master/main branch"

  # make a temp file in an appropriate spot, with a significant name
  let
    temp = createTemporaryFile(target.package, dotNimble)
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

      # if we haven't set the new version yet, bump the version number
      if not next.isValid:
        let
          bumped = last.get.bumpVersion(major, minor, patch)
        if bumped.isNone:
          crash "version unchanged; specify major, minor, or patch"
        else:
          debug "next version is", bumped.get
        next = bumped.get

      # make a subtle edit to the version string and write it out
      writer.writeLine next.withCrazySpaces(line)

  # for sanity, make sure we were able to parse the previous version
  if last.isNone:
    crash &"couldn't find a version statement in `{target}`"

  # and check again to be certain that our next version is valid
  if not next.isValid:
    crash &"unable to calculate the next version; `{next}` invalid"

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
    debug &"copying {temp} over {target}"
    copyFile(temp, $target)
  except Exception as e:
    discard e # noqa 😞
    crash &"failed to copy `{temp}` to `{target}`: {e.msg}"

  # try to do some git operations
  block nimgitsfu:
    # commit just the .nimble file, or the whole repository
    let
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

proc projectVersion*(hint = ""): Option[Version] {.compileTime.} =
  ## try to get the version from the current (compile-time) project
  let
    target = findTargetWith(macros.getProjectPath(), safeCurrentDir, hint)

  if target.found.isNone:
    macros.warning target.message
    macros.error &"provide the name of your project, minus {dotNimble}"
  var
    nimble = staticRead $target.found.get
  if nimble == "":
    macros.error &"missing/empty {dotNimble}; what version is this?!"
  result = parseVersion(nimble)

when isMainModule:
  import cligen

  let
    logger = newCuteConsoleLogger()
  addHandler(logger)

  const logo = """

      __
     / /_  __  ______ ___  ____
    / __ \/ / / / __ `__ \/ __ \
   / /_/ / /_/ / / / / / / /_/ /
  /_.___/\__,_/_/ /_/ /_/ .___/
                       /_/

  Increment the version of a nimble package, tag it, and push it via git

  Usage:
    bump [optional-params] [message: string...]

  """
  # find the version of bump itself, whatfer --version reasons
  const
    version = projectVersion()
  if version.isSome:
    clCfg.version = $version.get
  else:
    clCfg.version = "(unknown version)"

  dispatchCf bump, cmdName = "bump", cf = clCfg, noHdr = true,
    usage = logo & "Options(opt-arg sep :|=|spc):\n$options",
    help = {
      "patch": "increment the patch version field",
      "minor": "increment the minor version field",
      "major": "increment the major version field",
      "dry-run": "just report the projected version",
      "commit": "also commit any other unstaged changes",
      "v": "prefix the version tag with an ugly `v`",
      "nimble": "specify the nimble file to modify",
      "folder": "specify the location of the nimble file",
      "release": "also use `hub` to issue a GitHub release",
      "log-level": "specify Nim logging level",
      "manual": "manually set the new version to #.#.#",
    }
