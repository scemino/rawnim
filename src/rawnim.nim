import std/[logging, parseopt, strutils, strformat]
import engine
import util
import system
import graphics
import lang
import resource
import datatype

type
  Settings = object
    datapath: string
    lang: Language
    part: int
    ega: bool
    demoJoy: bool

const
  Usage = """
rawnim - Another World/Out of This World engine reimplementation written in pure nim.

Usage:
  rawnim [options]

Options:  
  --help,          -h        Shows this help and quits
  --datapath:path, -d:path   Path to data files (default '.')
  --language=lang, -l:lang   Language (fr,us)
  --part=num,      -p:num    Game part to start from (0-35 or 16001-16009)
  --ega            -e        Use EGA palette
  --demo3-joy      -j        Use inputs from 'demo3.joy' (DOS demo)
"""

proc runGame(settings: Settings) =
  var sys = new (System)
  var gfx = new (GraphicsObj)
  sys.init(getGameTitle(settings.lang))
  var e = newEngine(settings.part, settings.datapath, settings.lang, settings.ega)
  e.setSystem(sys, gfx)
  if settings.demoJoy and e.res.dataType == DT_DOS:
    e.res.readDemo3Joy()
  e.setup()
  while not sys.pi.quit:
    e.run()
  e.finish()

proc writeHelp() =
  echo Usage
  quit(0)

proc parseLanguage(lang: string): Language =
  case lang
  of "fr":
    result = French
  of "us":
    result = American
  else:
    stderr.write &"Invalid lang: {lang}"
    quit(1)

proc parseGameOptions(): Settings =
  var settings = Settings(datapath: ".", lang: French, part: 16001)
  var p = initOptParser()

  # parse options
  for kind, key, val in p.getopt():
    case kind
    of cmdEnd: doAssert(false)  # Doesn't happen with getopt()
    of cmdShortOption, cmdLongOption:
      case normalize(key)
      of "h", "help":
        writeHelp()
      of "d", "datapath":
        settings.datapath = val
      of "g", "debug":
        g_debugMask = {DBG_SCRIPT, DBG_BANK, DBG_VIDEO, DBG_SND, DBG_SER, DBG_INFO, DBG_PAK, DBG_RESOURCE}
      of "l", "language":
        settings.lang = parseLanguage(val)
      of "p", "part":
        settings.part = parseInt(val)
      of "e", "ega":
        settings.ega = true
      of "j", "demo3-joy":
        settings.demoJoy = true
    of cmdArgument:
      writeHelp()
  
  result = settings

when isMainModule:
  addHandler newConsoleLogger()
  let settings = parseGameOptions()
  runGame(settings)
