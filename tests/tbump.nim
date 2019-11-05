import os
import strutils
import options
import unittest

import bump

suite "bump":
  setup:
    let
      ver123 {.used.} = (major: 1'u, minor: 2'u, patch: 3'u)
      ver155 {.used.} = (major: 1'u, minor: 5'u, patch: 5'u)
      ver170 {.used.} = (major: 1'u, minor: 7'u, patch: 0'u)
      ver171 {.used.} = (major: 1'u, minor: 7'u, patch: 1'u)
      ver456 {.used.} = (major: 4'u, minor: 5'u, patch: 6'u)
      ver457 {.used.} = (major: 4'u, minor: 5'u, patch: 7'u)
      ver789 {.used.} = (major: 7'u, minor: 8'u, patch: 9'u)
      ver799 {.used.} = (major: 7'u, minor: 9'u, patch: 9'u)
      aList {.used.} = ""
      bList {.used.} = """
        v.1.2.3
        V.4.5.6
        v7.8.9
        V10.11.12
      """.unindent.strip
      cList {.used.} = """
        v.1.2.3
        4.5.6
        v7.8.9
        V10.11.12
        12.13.14
      """.unindent.strip
      crazy {.used.} = @[
        """version="1.2.3"""",
        """version      = "1.2.3"""",
        """version	 			 	= 	 		  "1.2.3"  """,
      ]

  test "parse version statement":
    for c in crazy:
      check ver123 == c.parseVersion.get

  test "substitute version into line with crazy spaces":
    for c in crazy:
      check ver123.withCrazySpaces(c) == c
    check ver123.withCrazySpaces("""version="4.5.6"""") == crazy[0]

  test "are we on the master branch":
    let
      isMaster = appearsToBeMasterBranch()
    check isMaster.isSome
    check isMaster.get

  test "all tags appear to start with v":
    check bList.allTagsAppearToStartWithV
    check not cList.allTagsAppearToStartWithV
    check not aList.allTagsAppearToStartWithV

  test "identify tags for arbitrary versions":
    let
      tagList = fetchTagList()
      isTagged {.used.} = ver170.taggedAs(tagList.get)
      notTagged {.used.} = ver155.taggedAs(tagList.get)
    check isTagged.isSome and isTagged.get == "1.7.0"
    check notTagged.isNone

  test "last tag in the tag list":
    expect ValueError:
      discard aList.lastTagInTheList
    check bList.lastTagInTheList == "V10.11.12"
    check cList.lastTagInTheList == "12.13.14"

  test "compose the right tag given strange input":
    let
      tagv171 {.used.} = composeTag(ver170, ver171, v = true, tags = aList)
      tag171 {.used.} = composeTag(ver170, ver171, v = false, tags = aList)
      tagv457 {.used.} = composeTag(ver456, ver457, tags = bList)
      tagv799 {.used.} = composeTag(ver789, ver799, tags = cList)
      tagv456 {.used.} = composeTag(ver123, ver456, tags = cList)
      tag457 {.used.} = composeTag(ver155, ver457, tags = cList)
      tagv155 {.used.} = composeTag(ver799, ver155, tags = bList)
    check tagv171.get == "v1.7.1"
    check tag171.get == "1.7.1"
    check tagv457.get == "V.4.5.7"
    check tagv799.get == "v7.9.9"
    check tagv456.get == "v.4.5.6"
    check tag457.get == "4.5.7"
    check tagv155.get == "V1.5.5"

  test "version validity checks out":
    check (0'u, 0'u, 0'u).isValid == false
    check (0'u, 0'u, 1'u).isValid == true

  test "strange user-supplied versions do not parse":
    check parseVersion("""version = "-1.2.3"""").isNone
    check parseVersion("""version = "12.3"""").isNone
    check parseVersion("""version = "123"""").isNone
    check parseVersion("""version = "steve"""").isNone
    check parseVersion("""version = "v0.3.0"""").isNone

  test "find a version at compile-time":
    const
      version = projectVersion()
    check version.isSome
    check $(version.get) != "0.0.0"

  test "find a nimble file from below":
    setCurrentDir(parentDir(currentSourcePath()))
    check fileExists(extractFilename(currentSourcePath()))
    let
      version = projectVersion()
    check version.isSome
    check $(version.get) != "0.0.0"
    let
      bumpy = findTarget(".", target = "bump")
      easy = findTarget(".", target = "")
      missing = findTarget("missing", target = "")
      randoR = findTarget("../tests/rando", target = "red")
      randoB = findTarget("../tests/rando", target = "blue")
      randoG = findTarget("../tests/rando", target = "green")
    for search in [bumpy, easy]:
      checkpoint search.message
      check search.found.isSome
      check search.found.get.repo.dirExists
      check search.found.get.package == "bump"
      check search.found.get.ext == ".nimble"
    for search in [missing, randoG]:
      checkpoint search.message
      check search.found.isNone
    for search in [randoR, randoB]:
      checkpoint search.message
      check search.found.isSome
    check randoR.found.isSome
    check randoR.found.get.package == "red"
    check randoB.found.isSome
    check randoB.found.get.package == "blue"
