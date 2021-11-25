import std/[logging, strformat]
import color
import system
import ptrmath
import util
import point
import quadstrip
import staticres

const
    COL_ALPHA = 0x10.byte # transparent pixel (OR'ed with 0x8)
    COL_PAGE  = 0x11.byte # buffer 0 pixel
    GFX_W = 320
    GFX_H = 200

type
    FixupPalette* = enum
        FIXUP_PALETTE_NONE,
        FIXUP_PALETTE_REDRAW # redraw all primitives on setPal script call
    GraphicsFormat* = enum
        FMT_CLUT,
        FMT_RGB555,
        FMT_RGB,
        FMT_RGBA
    Graphics* = ref GraphicsObj
    GraphicsObj* = object
        fixUpPalette*: FixupPalette
        pal: array[16, Color]
        byteDepth: int
        pagePtrs: array[4, seq[byte]]
        drawPagePtr: ptr byte
        colorBuffer: seq[uint16]
        w, h: int
        u, v: int

proc getPageSize(self: Graphics): int {.inline.} = 
    result = self.w * self.h * self.byteDepth

proc getPagePtr(self: Graphics, page: byte): ptr byte =
    self.pagePtrs[page.int][0].addr

proc setWorkPagePtr*(self: Graphics, page: byte) =
    self.drawPagePtr = self.getPagePtr(page)

proc setSize(self: Graphics, w, h: int) =
    self.u = (w shl 16) div 320
    self.v = (h shl 16) div 200
    self.w = w
    self.h = h
    self.byteDepth = 1
    assert(self.byteDepth == 1 or self.byteDepth == 2)
    self.colorBuffer = newSeq[uint16](self.w * self.h)
    for i in 0..<4:
        self.pagePtrs[i] = newSeq[byte](self.getPageSize())
    self.setWorkPagePtr(2)

proc init*(self: Graphics, targetW, targetH: int) =
    self.setSize(targetW, targetH)

proc setPalette*(self: Graphics, colors: array[16, Color], count: int) =
    copyMem(addr self.pal[0], unsafeaddr colors[0], sizeof(Color) * min(count, 16))

func xScale(self: Graphics, x: int): int =
    (x * self.u) shr 16

func yScale(self: Graphics, y: int): int =
    (y * self.v) shr 16

proc copyBuffer*(self: Graphics, dst, src: int, vscroll = 0) =
    if vscroll == 0:
        copyMem(self.getPagePtr(dst.byte), self.getPagePtr(src.byte), self.getPageSize())
    elif vscroll >= -199 and vscroll <= 199:
        let dy = self.yScale(vscroll)
        if dy < 0:
            copyMem(self.getPagePtr(dst.byte), self.getPagePtr(src.byte) - dy * self.w * self.byteDepth, (self.h + dy) * self.w * self.byteDepth)
        else:
            copyMem(self.getPagePtr(dst.byte) + dy * self.w * self.byteDepth, self.getPagePtr(src.byte), (self.h - dy) * self.w * self.byteDepth)

proc dumpPalette555(dest: ptr uint16,  w: int, pal: array[16, Color]) =
  var dst = dest
  const SZ = 16
  for color in 0..<16:
    var p = dst + ((color and 7) * SZ).int
    for y in 0..<SZ:
      for x in 0..<SZ:
        p[x] = pal[color].rgb555()
      p += w;
    if color == 7:
      dst += SZ * w

proc drawBuffer*(self: Graphics, num: int, sys: System) =
    var w, h: int
    var ar: array[4, float]
    sys.prepareScreen(w, h, ar)
    if self.byteDepth == 1:
        var src = self.getPagePtr(num.byte)
        for i in 0..<(self.w * self.h):
            self.colorBuffer[i] = self.pal[src[i]].rgb555()
        #dumpPalette555(addr self.colorBuffer[0], self.w, self.pal);
        sys.setScreenPixels555(self.colorBuffer[0].addr, self.w, self.h)
    elif self.byteDepth == 2:
        var src = cast[ptr uint16](self.getPagePtr(num.byte))
        sys.setScreenPixels555(src, self.w, self.h)
    sys.updateScreen()

proc drawBitmap*(self: Graphics, buffer: int, data: ptr byte, w, h: int, fmt: GraphicsFormat) =
    case self.byteDepth:
    of 1:
        if fmt == FMT_CLUT and self.w == w and self.h == h:
            copyMem(self.getPagePtr(buffer.byte), data, w * h)
            return
    of 2:
        if fmt == FMT_RGB555 and self.w == w and self.h == h:
            copyMem(self.getPagePtr(buffer.byte), data, self.getPageSize())
            return
    else: 
        discard
    warn &"GraphicsSoft::drawBitmap() unhandled fmt {fmt} w {w} h {h}"

proc clearBuffer*(self: Graphics, num: int, color: byte) =
    var p = self.getPagePtr(num.byte)
    p.fill(color, self.getPageSize())

proc drawPoint*(self: Graphics, xx, yy: int16, color: byte) =
    let x = self.xScale(xx.int)
    let y = self.yScale(yy.int)
    let offset = (y * self.w + x) * self.byteDepth
    case color:
    of COL_ALPHA:
        self.drawPagePtr[offset] = self.drawPagePtr[offset] or 8
    of COL_PAGE:
        self.drawPagePtr[offset] = self.pagePtrs[0][offset]
    else:
        self.drawPagePtr[offset] = color

proc drawPoint*(self: Graphics, buffer: int, color: byte, pt: Point) =
    self.setWorkPagePtr(buffer.byte)
    self.drawPoint(pt.x, pt.y, color)

proc drawLineP(self: Graphics, x1, x2, y: int16, color: byte) =
    if self.drawPagePtr == addr self.pagePtrs[0]:
        return
    var xmax = max(x1, x2)
    var xmin = min(x1, x2)
    let w = xmax - xmin + 1
    let offset = (y * self.w + xmin) * self.byteDepth
    copyMem(self.drawPagePtr + offset, addr self.pagePtrs[0][offset], w * self.byteDepth)

proc drawLineT(self: Graphics, x1, x2, y: int16, color: byte) = 
    var xmax = max(x1, x2)
    var xmin = min(x1, x2)
    var w = xmax - xmin + 1
    let offset = (y * self.w + xmin) * self.byteDepth
    for i in 0..<w:
        self.drawPagePtr[offset + i] = self.drawPagePtr[offset + i] or 8

proc drawLineN(self: Graphics, x1, x2, y: int16, color: byte) = 
    let xmax = max(x1, x2)
    let xmin = min(x1, x2)
    let w = xmax - xmin + 1
    let offset = (y * self.w + xmin) * self.byteDepth
    var p = self.drawPagePtr + offset
    p.fill(color, w)

func calcStep(p1, p2: Point, dy: var uint16): uint32 =
    dy = (p2.y - p1.y).uint16
    var delta = if dy <= 1: 1.uint16 else: dy
    ((p2.x - p1.x).uint32 * cast[uint32](0x4000 div delta)) shl 2

func decrement(v: var uint16): bool =
    result = v != 0
    dec v

proc drawPolygon*(self: Graphics, color: byte, quadStrip: QuadStrip) =
    var qs = quadStrip
    if self.w != GFX_W or self.h != GFX_H:
        for i in 0..<qs.numVertices.int:
            qs.vertices[i].scale(self.u, self.v)

    var i = 0
    var j = qs.numVertices - 1;

    var x2 = qs.vertices[i].x
    var x1 = qs.vertices[j].x
    var hliney = min(qs.vertices[i].y, qs.vertices[j].y)

    i += 1
    j -= 1

    var pdl: proc (self: Graphics, x1, x2, y: int16, color: byte)
    case color:
    of COL_PAGE:
        pdl = drawLineP
    of COL_ALPHA:
        pdl = drawLineT
    else:
        pdl = drawLineN

    var cpt1 = x1.uint32 shl 16
    var cpt2 = x2.uint32 shl 16

    var numVertices = qs.numVertices
    while true:
        numVertices -= 2
        if numVertices == 0:
            return
        var h: uint16
        var step1 = calcStep(qs.vertices[j + 1], qs.vertices[j], h)
        var step2 = calcStep(qs.vertices[i - 1], qs.vertices[i], h)
        
        i += 1
        j -= 1

        cpt1 = (cpt1 and 0xFFFF0000.uint32) or 0x7FFF
        cpt2 = (cpt2 and 0xFFFF0000.uint32) or 0x8000

        if h == 0:
            cpt1 += step1
            cpt2 += step2
        else:
            while decrement(h):
                if hliney >= 0:
                    x1 = cast[int16](cpt1 shr 16)
                    x2 = cast[int16](cpt2 shr 16)
                    if x1 < self.w and x2 >= 0:
                        if x1 < 0: x1 = 0
                        if x2 >= self.w: x2 = self.w.int16 - 1.int16
                        self.pdl(x1, x2, hliney, color)
                cpt1 += step1
                cpt2 += step2
                hliney += 1
                if hliney >= self.h: return

proc drawQuadStrip*(self: Graphics, buffer: byte, color: byte, qs: QuadStrip) =
    self.setWorkPagePtr(buffer)
    self.drawPolygon(color, qs)

proc drawChar(self: Graphics, c: char, xx, yy: uint16, color: byte) =
    if xx <= GFX_W - 8 and yy <= GFX_H - 8:
        var x = self.xScale(xx.int)
        var y = self.yScale(yy.int)
        var ftOffset = ((cast[int](c) - 0x20) * 8).int
        var offset = (x + y * self.w) * self.byteDepth
        if self.byteDepth == 1:
            for j in 0..<8:
                var ch = font[ftOffset + j]
                for i in 0..<8:
                    if (ch.int and (1 shl (7 - i))) != 0:
                        self.drawPagePtr[offset + j * self.w + i] = color

proc drawStringChar*(self: Graphics, buffer: byte, color: byte, c: char, pt: Point) =
    self.setWorkPagePtr(buffer)
    self.drawChar(c, pt.x.uint16, pt.y.uint16, color)
