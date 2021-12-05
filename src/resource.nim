import std/[logging, options, os, streams, strformat]
import util
import unpack
import ptrmath
import video
import staticres
import datatype

const
    EntriesCount = 146
    MemBlockSize = 1024 * 1024
    memListParts = [
        [ 0x14, 0x15, 0x16, 0x00 ], # 16000 - protection screens
        [ 0x17, 0x18, 0x19, 0x00 ], # 16001 - introduction
        [ 0x1A, 0x1B, 0x1C, 0x11 ], # 16002 - water
        [ 0x1D, 0x1E, 0x1F, 0x11 ], # 16003 - jail
        [ 0x20, 0x21, 0x22, 0x11 ], # 16004 - 'cite'
        [ 0x23, 0x24, 0x25, 0x00 ], # 16005 - 'arene'
        [ 0x26, 0x27, 0x28, 0x11 ], # 16006 - 'luxe'
        [ 0x29, 0x2A, 0x2B, 0x11 ], # 16007 - 'final'
        [ 0x7D, 0x7E, 0x7F, 0x00 ], # 16008 - password screen
        [ 0x7D, 0x7E, 0x7F, 0x00 ]  # 16009 - password screen
    ]
    STATUS_NULL* = 0
    STATUS_LOADED* = 1
    STATUS_TOLOAD* = 2

type
    MemEntry = object
        status*: byte          # 0x0
        entryType*: byte       # 0x1, Resource::ResType
        bufPtr*: ptr byte      # 0x2
        rankNum: byte         # 0x6
        bankNum: byte         # 0x7
        bankPos: uint32       # 0x8
        packedSize: uint32    # 0xC
        unpackedSize: uint32  # 0x12
    Resource* = ref ResourceObj
    ResourceObj* = object
        vid*: Video
        datapath: string
        memList*: array[EntriesCount+1, MemEntry]
        hasPasswordScreen*: bool
        currentPart*, nextPart*: uint16
        memPtrStart, scriptBakPtr, scriptCurPtr, vidBakPtr, vidCurPtr: ptr byte
        memPtr: seq[byte]
        useSegVideo2*: bool
        segVideoPal*, segCode*, segVideo1*, segVideo2*: ptr byte
        dataType*: DataType
        amigaMemList: AmigaMemEntries
        numMemList: int
        bankPrefix: string
        demo3Joy*: DemoJoy
    ResourceRef* = ref Resource
    ResType = enum
        RT_SOUND = 0,
        RT_MUSIC  = 1,
        RT_BITMAP = 2, # full screen 4bpp video buffer, size=200*320/2
        RT_PALETTE = 3, # palette (1024=vga + 1024=ega), size=2048
        RT_BYTECODE = 4,
        RT_SHAPE = 5,
        RT_BANK = 6, # common part shapes (bank2.mat)
    DemoJoy* = object
        keymask: byte
        counter: byte
        bufPtr: seq[byte]
        bufPos, bufSize: int

proc start*(self: var DemoJoy): bool =
    if self.bufSize > 0:
        self.keymask = self.bufPtr[0]
        self.counter = self.bufPtr[1]
        self.bufPos = 2
        result = true
    result = false

proc update*(self: var DemoJoy): byte =
    if self.bufPos >= 0 and self.bufPos < self.bufSize:
        if self.counter == 0:
            self.keymask = self.bufPtr[self.bufPos]
            self.counter = self.bufPtr[self.bufPos + 1]
            self.bufPos += 2
        else:
            dec self.counter
        return self.keymask
    return 0

proc getBankName(self: Resource, bankNum: byte): string =
    # HACK: don't know why joinPath does not work here
    result = &"{self.datapath}{DirSep}{self.bankPrefix}{bankNum:02X}"

proc detectAmigaAtari(self: Resource, stream: var Stream): Option[AmigaMemEntries] =
    const entries = [
        (size: 244674, mem: memListAmigaFr),
        (size: 244868, mem: memListAmigaEn),
        (size: 227142, mem: memListAtariEn),
    ]
    let path = self.getBankName(1)
    if fileExists(path):
        let size = getFileSize(path)
        for entry in entries:
            if entry.size == size:
                return some(entry.mem)
    return none(AmigaMemEntries)

proc getMemListPath(self: Resource): string =
    result = &"{self.datapath}{DirSep}memlist.bin"

proc getDemoPath(self: Resource): string =
    result = &"{self.datapath}{DirSep}demo01"

proc getDemoJoyPath(self: Resource): string =
    result = &"{self.datapath}{DirSep}demo3.joy"

proc detectVersion(self: Resource) =
    if fileExists(self.getMemListPath()):
        self.dataType = DT_DOS
        debug(DBG_INFO, "Using DOS data files")
    else:
        var stream: Stream
        var memList = self.detectAmigaAtari(stream)
        if memList.isSome:
            self.dataType = if memList.get() == memListAtariEn: DT_ATARI else: DT_AMIGA
            self.amigaMemList = memList.get()
            if self.dataType == DT_AMIGA:
                debug(DBG_INFO, "Using Amiga data files")
            else:
                debug(DBG_INFO, "Using Atari data files")

proc newResource*(datapath: string): Resource =
    result = new(Resource)
    result.datapath = datapath
    result.bankPrefix = "bank"
    result.detectVersion()

proc allocMemBlock*(self: Resource) =
    self.memPtr = newSeq[byte](MemBlockSize)
    self.memPtrStart = addr self.memPtr[0]
    self.scriptCurPtr = self.memPtrStart
    self.scriptBakPtr = self.memPtrStart
    self.vidCurPtr = self.memPtrStart + MemBlockSize - 0x800 * 16
    self.vidBakPtr = self.vidCurPtr
    self.useSegVideo2 = false

proc readEntriesAmiga(self: Resource, entries: AmigaMemEntries) =
    for i in 0..<entries.len:
        self.memList[i].entryType = entries[i].entryType
        self.memList[i].bankNum = entries[i].bank
        self.memList[i].bankPos = entries[i].offset
        self.memList[i].packedSize = entries[i].packedSize
        self.memList[i].unpackedSize = entries[i].unpackedSize
    self.memList[entries.len].status = 0xFF
    self.numMemList = entries.len

proc readEntries*(self: Resource) =
    case self.dataType:
    of DT_DOS:
        if fileExists(self.getDemoPath()):
            self.bankPrefix = "demo"
        let path = self.getMemListPath()
        if not fileExists(path):
            quit &"File {path} does not exit"
        var f = openFileStream(path)
        for i in 0..EntriesCount:
            self.memList[i].status = f.readUint8()
            self.memList[i].entryType = f.readUint8()
            discard f.readUint32BE()
            self.memList[i].rankNum = f.readUint8()
            self.memList[i].bankNum = f.readUint8()
            self.memList[i].bankPos = f.readUint32BE()
            self.memList[i].packedSize = f.readUint32BE()
            self.memList[i].unpackedSize = f.readUint32BE()
            if self.memList[i].status == 0xFF:
                const num = memListParts[8][1] # 16008 bytecode
                let bank = self.getBankName(self.memList[num].bankNum)
                self.hasPasswordScreen = fileExists(bank)
                break
            inc self.numMemList
        f.close()
    of DT_AMIGA, DT_ATARI:
        self.hasPasswordScreen = true
        self.readEntriesAmiga(self.amigaMemList)

proc readBank(self: Resource, me: MemEntry, dstBuf: ptr byte): bool =
    result = false
    let bank = self.getBankName(me.bankNum)
    if fileExists(bank):
        var f = openFileStream(bank)
        f.setPosition(me.bankPos.int)
        let count = f.readData(dstBuf, me.packedSize.int)
        result = count == me.packedSize.int
        if result and me.packedSize != me.unpackedSize:
            result = bytekiller_unpack(dstBuf, me.unpackedSize.int, dstBuf, me.packedSize.int)
    else:
        debug(DBG_BANK, &"File {bank} DOESN'T exits")

proc dumpFile(filename: string, p: seq[byte], size: int) =
    createDir "DUMP"
    let path = &"DUMP/{filename}"
    var fp = open(path, fmWrite)
    discard fp.writeBytes(p, 0, size)
    fp.close()

proc dumpEntries*(self: Resource) =
    for i in 0..<self.numMemList:
        if self.memList[i].unpackedSize != 0:
            continue
        if self.memList[i].bankNum == 5 and (self.dataType == DT_AMIGA or self.dataType == DT_ATARI):
            continue
        var p = newSeq[byte](self.memList[i].unpackedSize)
        let name = &"data_{i:02x}_{self.memList[i].entryType}"
        if self.readBank(self.memList[i], addr p[0]):
            debug &"Dump file {name}"
            dumpFile(name, p, self.memList[i].unpackedSize.int)
        else:
            debug &"{name} read failed"

proc invalidateRes*(self: Resource) =
    for i in 0..<self.numMemList:
        var me = addr self.memList[i]
        if (me.entryType <= 2 or me.entryType > 6):
            me.status = STATUS_NULL
    self.scriptCurPtr = self.scriptBakPtr
    self.vid.currentPal = 0xFF

proc invalidateAll(self: Resource) =
    for i in 0..<self.numMemList:
        self.memList[i].status = STATUS_NULL
    self.scriptCurPtr = self.memPtrStart

proc load(self: Resource) =
    while true:
        var me : ptr MemEntry

        # get resource with max rankNum
        var maxNum = 0.byte
        var resourceNum = 0
        for i in 0..<self.numMemList:
            var it = addr self.memList[i]
            if it.status == STATUS_TOLOAD and maxNum <= it.rankNum:
                maxNum = it.rankNum
                me = it
                resourceNum = i
        if me == nil:
            debug(DBG_BANK, "Resource::load() => no entry found")
            break # no entry found

        var memPtr: ptr byte
        if me.entryType == RT_BITMAP.byte:
            memPtr = self.vidCurPtr
        else:
            memPtr = self.scriptCurPtr
            if me.unpackedSize > (cast[uint32](self.vidBakPtr) - cast[uint32](self.scriptCurPtr)).uint32:
                warn "Resource::load() not enough memory"
                me.status = STATUS_NULL
                continue
        if me.bankNum == 0:
            warn "Resource::load() ec=0xF00 (me.bankNum == 0)"
            me.status = STATUS_NULL
        else:
            let bufPos = cast[int](memPtr) - cast[int](self.memPtrStart)
            debug(DBG_BANK, &"Resource::load() bufPos=0x{bufPos:0X} size={me.packedSize}/unpackedSize={me.unpackedSize} type={me.entryType} pos=0x{me.bankPos:X} bankNum={me.bankNum}")
            if self.readBank(me[], memPtr):
                if me.entryType == RT_BITMAP.byte:
                    self.vid.copyBitmapPtr(self.vidCurPtr, me.unpackedSize)
                    me.status = STATUS_NULL
                else:
                    me.bufPtr = memPtr
                    me.status = STATUS_LOADED
                    self.scriptCurPtr += me.unpackedSize.int
            else:
                if self.dataType == DT_DOS and me.bankNum == 12 and me.entryType == RT_BANK.byte:
                    # DOS demo version does not have the bank for this resource
                    # this should be safe to ignore as the resource does not appear to be used by the game code
                    me.status = STATUS_NULL
                    continue
                error &"Unable to read resource {resourceNum} from bank {me.bankNum}"

proc setupPart*(self: Resource, ptrId: int) =
    if ptrId.uint16 != self.currentPart:
        var
            ipal = 0.byte
            icod = 0.byte
            ivd1 = 0.byte
            ivd2 = 0.byte
        if ptrId >= 16000 and ptrId <= 16009:
            var part = (ptrId - 16000).uint16
            ipal = memListParts[part][0].byte
            icod = memListParts[part][1].byte
            ivd1 = memListParts[part][2].byte
            ivd2 = memListParts[part][3].byte
        else:
            error &"Resource::setupPart() ec=0x{0xF07:X} invalid part"
        self.invalidateAll()
        self.memList[ipal].status = STATUS_TOLOAD
        self.memList[icod].status = STATUS_TOLOAD
        self.memList[ivd1].status = STATUS_TOLOAD
        if ivd2 != 0:
            self.memList[ivd2].status = STATUS_TOLOAD
        self.load()
        self.segVideoPal = self.memList[ipal].bufPtr
        self.segCode = self.memList[icod].bufPtr
        self.segVideo1 = self.memList[ivd1].bufPtr
        if ivd2 != 0:
            self.segVideo2 = self.memList[ivd2].bufPtr
        self.currentPart = ptrId.uint16
    self.scriptBakPtr = self.scriptCurPtr

proc update*(self: Resource, num: uint16) =
    if num > 16000:
        self.nextPart = num
    elif self.memList[num].status == STATUS_NULL:
        self.memList[num].status = STATUS_TOLOAD
        self.load()

proc readDemo3Joy*(self: Resource) =
    let path = self.getDemoJoyPath()
    if fileExists(path):
        var f = openFileStream(path)
        let fileSize = getFileSize(path)
        self.demo3Joy.bufPtr = newSeq[byte](fileSize)
        self.demo3Joy.bufSize = f.readData(addr self.demo3Joy.bufPtr[0], fileSize.int)
        self.demo3Joy.bufPos = -1
    else:
        warn &"Unable to open '{path}'"

when isMainModule:
  addHandler newConsoleLogger()
  var r = Resource()
  r.readEntries()
  r.dumpEntries()
