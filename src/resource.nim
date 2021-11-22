import std/[logging, os, streams, strformat]
import util
import unpack
import ptrmath
import video

const
    EntriesCount = 146
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
    STATUS_NULL = 0
    STATUS_LOADED = 1
    STATUS_TOLOAD = 2

type
    MemEntry = object
        status: byte          # 0x0
        entryType: byte       # 0x1, Resource::ResType
        bufPtr: ptr byte      # 0x2
        rankNum: byte         # 0x6
        bankNum: byte         # 0x7
        bankPos: uint32       # 0x8
        packedSize: uint32    # 0xC
        unpackedSize: uint32  # 0x12
    Resource* = object
        vid: Video
        memList: array[EntriesCount+1, MemEntry]
        hasPasswordScreen: bool
        currentPart*, nextPart*: uint16
        memPtrStart, scriptBakPtr, scriptCurPtr, vidBakPtr, vidCurPtr: ptr byte
        useSegVideo2*: bool
        segVideoPal, segCode*, segVideo1*, segVideo2*: ptr byte
    ResType = enum
        RT_SOUND = 0,
        RT_MUSIC  = 1,
        RT_BITMAP = 2, # full screen 4bpp video buffer, size=200*320/2
        RT_PALETTE = 3, # palette (1024=vga + 1024=ega), size=2048
        RT_BYTECODE = 4,
        RT_SHAPE = 5,
        RT_BANK = 6, # common part shapes (bank2.mat)

proc getBankName(bankNum: byte): string =
    result = &"bank{bankNum:02X}"

proc readEntries*(self: var Resource) =
    info "Read entries"
    var f = openFileStream("memlist.bin")
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
            let bank = getBankName(self.memList[num].bankNum)
            self.hasPasswordScreen = fileExists(bank)
            echo "hasPasswordScreen: ", self.hasPasswordScreen
            break
    f.close()

proc readBank(self: Resource, me: MemEntry, dstBuf: ptr byte): bool =
    result = false
    let bank = getBankName(me.bankNum)
    if fileExists(bank):
        debug &"File {bank} exits"  
        var f = openFileStream(bank)
        f.setPosition(me.bankPos.int)
        let count = f.readData(dstBuf, me.packedSize.int)
        result = count == me.packedSize.int
        if result and me.packedSize != me.unpackedSize:
            result = bytekiller_unpack(dstBuf, me.unpackedSize.int, dstBuf, me.packedSize.int)
    else:
        debug &"File {bank} DOESN'T exits"

proc dumpFile(filename: string, p: seq[byte], size: int) =
    createDir "DUMP"
    let path = &"DUMP/{filename}"
    var fp = open(path, fmWrite)
    discard fp.writeBytes(p, 0, size)
    fp.close()

proc dumpEntries*(self: Resource) =
    for i in 0..<self.memList.len:
        if self.memList[i].unpackedSize == 0:
            continue
        var p = newSeq[byte](self.memList[i].unpackedSize)
        let name = &"data_{i:02x}_{self.memList[i].entryType}"
        if self.readBank(self.memList[i], addr p[0]):
            debug &"Dump file {name}"
            dumpFile(name, p, self.memList[i].unpackedSize.int)
        else:
            debug &"{name} read failed"

proc invalidateRes*(self: var Resource) =
    for i in 0..<self.memList.len:
        var me = self.memList[i]
        if (me.entryType <= 2 or me.entryType > 6):
            me.status = STATUS_NULL
    self.scriptCurPtr = self.scriptBakPtr
    self.vid.currentPal = 0xFF

proc invalidateAll(self: var Resource) =
    for i in 0..<self.memList.len:
        self.memList[i].status = STATUS_NULL
    self.scriptCurPtr = self.memPtrStart

proc load(self: var Resource) =
    while true:
        var me : ptr MemEntry

        # get resource with max rankNum
        var maxNum = 0.byte
        var resourceNum = 0
        for i in 0..<self.memList.len:
            var it = addr self.memList[i]
            if it.status == STATUS_TOLOAD and maxNum <= it.rankNum:
                maxNum = it.rankNum
                me = it
                resourceNum = i
        if me == nil:
            break # no entry found

        var memPtr: ptr byte
        if me.entryType == RT_BITMAP.byte:
            memPtr = self.vidCurPtr
        else:
            memPtr = self.scriptCurPtr
            if me.unpackedSize > (cast[uint32](self.vidBakPtr) - cast[uint32](self.scriptCurPtr)).uint32:
                # TODO: warning "Resource::load() not enough memory"
                me.status = STATUS_NULL
                continue
        if me.bankNum == 0:
            # TODO: warning "Resource::load() ec=0xF00 (me.bankNum == 0)"
            me.status = STATUS_NULL
        else:
            #TODO: debug (DBG_BANK, "Resource::load() bufPos=0x%X size=%d type=%d pos=0x%X bankNum=%d", memPtr - self.memPtrStart, me.packedSize, me.entryType, me.bankPos, me.bankNum)
            if self.readBank(me[],memPtr):
                if me.entryType == RT_BITMAP.byte:
                    self.vid.copyBitmapPtr(self.vidCurPtr, me.unpackedSize)
                    me.status = STATUS_NULL
                else:
                    me.bufPtr = memPtr
                    me.status = STATUS_LOADED
                    self.scriptCurPtr += me.unpackedSize.int
            else:
                if me.bankNum == 12 and me.entryType == RT_BANK.byte:
                    # DOS demo version does not have the bank for this resource
                    # this should be safe to ignore as the resource does not appear to be used by the game code
                    me.status = STATUS_NULL
                    continue
                error &"Unable to read resource {resourceNum} from bank {me.bankNum}"

proc setupPart*(self: var Resource, ptrId: int) =
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

proc update*(self: var Resource, num: uint16) =
    if num > 16000:
        self.nextPart = num
        return
    var me = self.memList[num]
    if me.status == STATUS_NULL:
        me.status = STATUS_TOLOAD
        self.load()

when isMainModule:
  addHandler newConsoleLogger()
  var r = Resource()
  r.readEntries()
  r.dumpEntries()
