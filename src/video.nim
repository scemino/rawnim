import ptrmath
import point
import graphics
import system

type Video* = object
    graphics*: Graphics
    displayHead*: bool
    nextPal*, currentPal*: byte
    
proc decode_amiga(source: ptr byte, dest: ptr byte) =
    var src = source
    var dst = dest
    const plane_size = 200 * 320 div 8
    for y in 0..<200:
        for x in countup(0, 320-1, 8):
            for b in 0..<8:
                let mask = 1 shl (7 - b)
                var color = 0
                for p in 0..<4:
                    if (src[p * plane_size] and mask.byte) > 0:
                        color = color or (1 shl p)
                dst[0] = color.byte
                dst += 1
            src += 1

proc init*(self: Video) =
    discard

proc copyBitmapPtr*(self: Video, src: ptr byte, size: uint32 = 0) =
    discard

proc setDataBuffer*(self: Video, dataBuf: ptr byte, offset: uint16) =
    discard

proc drawShape*(self: Video, color: byte, zoom: uint16, pt: ptr Point) =
    discard

proc drawString*(self: Video, color: byte, x, y, strId: uint16) =
    discard

proc changePal*(self: Video, pal: int) =
    discard

proc setWorkPagePtr*(self: Video, page: byte) =
    discard

proc fillPage*(self: Video, page, color: byte) =
    discard

proc copyPage*(self: Video, page, dst: byte, vscroll: int16) =
    discard

proc updateDisplay*(self: Video, page: byte, sys: System) =
    discard