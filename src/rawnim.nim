import std/logging
import engine
import util
import system
import graphics

when isMainModule:
  g_debugMask = {DBG_SCRIPT, DBG_BANK, DBG_VIDEO, DBG_SND, DBG_SER, DBG_INFO, DBG_PAK, DBG_RESOURCE}
  const part = 16001
  addHandler newConsoleLogger()
  var sys = new (System)
  var gfx = new (GraphicsObj)
  sys.init("Another world")
  var e = newEngine(part)
  e.setSystem(sys, gfx)
  e.setup()
  while true:
    e.run()
  e.finish()
  
  # var pal1 = [Color(r: 17, g: 17, b: 17), Color(r: 136, g: 0, b: 0), Color(r: 17, g: 34, b: 68), Color(r: 17, g: 51, b: 85), Color(r: 34, g: 68, b: 102), Color(r: 51, g: 85, b: 119), Color(r: 85, g: 119, b: 153), Color(r: 119, g: 170, b: 187), Color(r: 187, g: 136, b: 0), Color(r: 255, g: 0, b: 0), Color(r: 204, g: 153, b: 0), Color(r: 221, g: 170, b: 0), Color(r: 238, g: 204, b: 0), Color(r: 255, g: 238, b: 0), Color(r: 255, g: 255, b: 119), Color(r: 255, g: 255, b: 170)]
  # gfx.setPalette(pal1, 16)
  
  # var qs : QuadStrip
  # qs.numVertices = 6
  # qs.vertices[0] = Point(x: 20, y: 0)
  # qs.vertices[1] = Point(x: 39, y: 15)
  # qs.vertices[2] = Point(x: 30, y: 49)
  # qs.vertices[3] = Point(x: 25, y: 49)
  # qs.vertices[4] = Point(x: 0, y: 15)
  # qs.vertices[5] = Point(x: 20, y: 0)

  # gfx.clearBuffer(1, 0)
  # gfx.setWorkPagePtr(1)
  # gfx.drawPolygon(1, qs)
  # e.vid.setWorkPagePtr(1)
  # e.vid.drawString(8, 0, 40, 0x190'u16)

  # while true:
  #   sys.processEvents()
  #   gfx.drawBuffer(1, sys)
