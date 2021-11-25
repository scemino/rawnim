import std/[logging, strformat]
import ptrmath
import graphics
import system
import util
import scriptptr
import color
import point
import quadstrip

const 
    BITMAP_W = 320
    BITMAP_H = 200

type 
    Video* = ref VideoObj
    VideoObj* = object
        graphics*: Graphics
        displayHead*: bool
        nextPal*, currentPal*: byte
        buffers: array[3, byte]
        pData: ScriptPtr
        dataBuf: ptr byte
        tempBitmap: seq[byte]
    
proc newVideo*(): Video =
    result = Video(tempBitmap: newSeq[byte](BITMAP_W * BITMAP_H))

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
                    if (src[p * plane_size] and mask.byte) != 0:
                        color = color or (1 shl p)
                dst[] = color.byte
                dst += 1
            src += 1

proc scaleBitmap(self: Video, src: ptr byte, fmt: GraphicsFormat) =
    self.graphics.drawBitmap(0, src, BITMAP_W, BITMAP_H, fmt)

proc getPagePtr(self: Video, page: byte): byte =
    var p: byte
    if page <= 3:
        p = page
    else:
        case page:
        of 0xFF:
            p = self.buffers[2]
        of 0xFE:
            p = self.buffers[1]
        else:
            p = 0 # XXX check
            warn &"Video::getPagePtr() p != [0,1,2,3,0xFF,0xFE] == 0x{page:X}"
    result = p

proc setWorkPagePtr*(self: Video, page: byte) =
    debug(DBG_VIDEO, &"Video::setWorkPagePtr({page})")
    self.buffers[0] = self.getPagePtr(page)

proc init*(self: Video) =
    self.currentPal = 0xFF
    self.nextPal = 0xFF
    self.buffers[2] = self.getPagePtr(1)
    self.buffers[1] = self.getPagePtr(2)
    self.setWorkPagePtr(0xFE)
    self.pData.byteSwap = false

proc copyBitmapPtr*(self: Video, src: ptr byte, size: uint32 = 0) =
    decode_amiga(src, self.tempBitmap[0].unsafeAddr)
    self.scaleBitmap(self.tempBitmap[0].addr, FMT_CLUT)

proc setDataBuffer*(self: Video, dataBuf: ptr byte, offset: uint16) =
    self.dataBuf = dataBuf
    self.pData.pc = dataBuf + offset.int

proc fillPolygon(self: Video, color, zoom: uint16, pt: Point) =
    var p = self.pData.pc

    var bbw = p[] * zoom div 64; p += 1
    var bbh = p[] * zoom div 64; p += 1
    
    var x1 = pt.x - bbw.int16 div 2
    var x2 = pt.x + bbw.int16 div 2
    var y1 = pt.y - bbh.int16 div 2
    var y2 = pt.y + bbh.int16 div 2

    if x1 > 319 or x2 < 0 or y1 > 199 or y2 < 0:
        return

    var qs: QuadStrip
    qs.numVertices = p[]; p += 1
    if (qs.numVertices and 1) != 0:
        warn &"Unexpected number of vertices {qs.numVertices}"
        return

    for i in 0..<qs.numVertices.int:
        qs.vertices[i].x = x1 + (p[] * zoom div 64).int16; p += 1
        qs.vertices[i].y = y1 + (p[] * zoom div 64).int16; p += 1

    if qs.numVertices == 4 and bbw == 0 and bbh <= 1:
        self.graphics.drawPoint(self.buffers[0].int, color.byte, pt)
    else:
        self.graphics.drawQuadStrip(self.buffers[0], color.byte, qs)

proc drawShapeParts(self: Video, zoom: uint16, pgc: Point)

proc drawShape*(self: Video, color: byte, zoom: uint16, pt: Point) =
    var i = self.pData.fetchByte()
    var c = color
    if i >= 0xC0:
        if (c and 0x80) != 0:
            c = (i and 0x3F).byte
        self.fillPolygon(c, zoom, pt)
    else:
        i = i and 0x3F
        if i == 1:
            warn "Video::drawShape() ec=0xF80 (i != 2)"
        elif i == 2:
            discard
            self.drawShapeParts(zoom, pt)
        else:
            warn "Video::drawShape() ec=0xFBB (i != 2)"

proc drawShapeParts(self: Video, zoom: uint16, pgc: Point) =
    var pt: Point
    pt.x = pgc.x - (self.pData.fetchByte() * zoom div 64).int16
    pt.y = pgc.y - (self.pData.fetchByte() * zoom div 64).int16
    var n = self.pData.fetchByte().int16
    debug(DBG_VIDEO, &"Video::drawShapeParts n={n}")
    for i in countdown(n, 0):
        var offset = self.pData.fetchWord()
        var po = pt
        po.x += (self.pData.fetchByte() * zoom div 64).int16
        po.y += (self.pData.fetchByte() * zoom div 64).int16
        var color = 0xFF.uint16
        if (offset and 0x8000) != 0:
            color = self.pData.fetchByte()
            discard self.pData.fetchByte()
            color = color and 0x7F
        offset = offset shl 1
        var bak = self.pData.pc
        self.pData.pc = self.dataBuf + offset.int
        self.drawShape(color.byte, zoom, po)
        self.pData.pc = bak

proc drawString*(self: Video, color: byte, x, y, strId: uint16) =
    assert(false)

proc fillPage*(self: Video, page, color: byte) =
    self.graphics.clearBuffer(self.getPagePtr(page).int, color)

proc copyPage*(self: Video, src, dst: byte, vscroll: int16) =
    debug(DBG_VIDEO, &"Video::copyPage({src}, {dst})")
    if src >= 0xFE: # no vscroll
        self.graphics.copyBuffer(self.getPagePtr(dst.byte).int, self.getPagePtr(src).int)
    else:
        var s = src and (not 0x40.byte)
        if (s and 0x80) == 0:
            self.graphics.copyBuffer(self.getPagePtr(dst.byte).int, self.getPagePtr(s).int)
        else:
            var sl = self.getPagePtr((s and 3).byte)
            var dl = self.getPagePtr(dst)
            if sl != dl and vscroll >= -199 and vscroll <= 199:
                self.graphics.copyBuffer(dl.int, sl.int, vscroll)

proc readPaletteAmiga(self: Video, buf: ptr byte, num: int, pal: var array[16, Color]) =
    var p = buf + num * 16 * sizeof(uint16)
    for i in 0..<16:
        let color = READ_BE_UINT16(p)
        p += 2
        let r = (color shr 8) and 0xF
        let g = (color shr 4) and 0xF
        let b =  color       and 0xF
        pal[i].r = (r shl 4) or r
        pal[i].g = (g shl 4) or g
        pal[i].b = (b shl 4) or b

proc changePal*(self: Video, segVideoPal: ptr byte, palNum: byte) =
    if palNum < 32 and palNum != self.currentPal:
        var pal : array[16, Color]
        self.readPaletteAmiga(segVideoPal, palNum.int, pal)
        self.graphics.setPalette(pal, 16)
        self.currentPal = palNum

proc updateDisplay*(self: Video, segVideoPal: ptr byte, page: byte, sys: System) =
    debug(DBG_VIDEO, &"Video::updateDisplay({page})")
    if page != 0xFE:
        if page == 0xFF:
            swap(self.buffers[1], self.buffers[2])
        else:
            self.buffers[1] = self.getPagePtr(page)
    if self.nextPal != 0xFF:
        self.changePal(segVideoPal, self.nextPal)
        self.nextPal = 0xFF
    self.graphics.drawBuffer(self.buffers[1].int, sys)
