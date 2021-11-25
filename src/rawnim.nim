import std/logging
import engine
import util
import system
import graphics
import sequtils
import ptrmath
import color


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
  
  # var colorBuffer = newSeq[uint16](320*200)
  # var pal1 = [(r: 17, g: 17, b: 17), (r: 136, g: 0, b: 0), (r: 17, g: 34, b: 68), (r: 17, g: 51, b: 85), (r: 34, g: 68, b: 102), (r: 51, g: 85, b: 119), (r: 85, g: 119, b: 153), (r: 119, g: 170, b: 187), (r: 187, g: 136, b: 0), (r: 255, g: 0, b: 0), (r: 204, g: 153, b: 0), (r: 221, g: 170, b: 0), (r: 238, g: 204, b: 0), (r: 255, g: 238, b: 0), (r: 255, g: 255, b: 119), (r: 255, g: 255, b: 170)]
  # var pal2 = pal1.mapIt(Color(r: it.r,g: it.g,b: it.b)).toSeq
  # dumpPalette555(addr colorBuffer[0], 320, pal2);
  
  # while true:
  #   sys.processEvents()
  #   # if self.byteDepth == 1:
  #   #     var src = self.getPagePtr(num.byte)
  #   #     for i in 0..<(self.w * self.h):
  #   #         self.colorBuffer[i] = self.pal[src[i]].rgb555()
  #   #     sys.setScreenPixels555(self.colorBuffer[0].addr, self.w, self.h)
  #   # elif self.byteDepth == 2:
  #   #     var src = cast[ptr uint16](self.getPagePtr(num.byte))
  #   #     sys.setScreenPixels555(src, self.w, self.h)
  #   sys.setScreenPixels555(addr colorBuffer[0], 320, 200)
  #   sys.updateScreen()
