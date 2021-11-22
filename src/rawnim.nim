import std/logging
import engine
import util

when isMainModule:
  g_debugMask = {DBG_SCRIPT, DBG_BANK, DBG_VIDEO, DBG_SND, DBG_SER, DBG_INFO, DBG_PAK, DBG_RESOURCE}
  const part = 16001
  addHandler newConsoleLogger()
  var e = newEngine(part)
  e.setup()
  while true:
    e.run()
  e.finish()
