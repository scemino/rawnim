import std/[logging, os, streams, strformat]
import util
import unpack

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
        memList: array[EntriesCount+1, MemEntry]
        hasPasswordScreen: bool

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

proc readBank(self: Resource, me: MemEntry, dstBuf: var seq[byte]): bool =
    result = false
    let bank = getBankName(me.bankNum)
    if fileExists(bank):
        debug &"File {bank} exits"  
        var f = openFileStream(bank)
        f.setPosition(me.bankPos.int)
        dstBuf.setLen(me.packedSize)
        let count = f.readData(addr dstBuf[0], me.packedSize.int)
        result = count == me.packedSize.int
        if result and me.packedSize != me.unpackedSize:
            result = bytekiller_unpack(addr dstBuf[0], me.unpackedSize.int, addr dstBuf[0], me.packedSize.int)
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
        if self.readBank(self.memList[i], p):
            debug &"Dump file {name}"
            dumpFile(name, p, self.memList[i].unpackedSize.int)
        else:
            debug &"{name} read failed"

when isMainModule:
  addHandler newConsoleLogger()
  var r = Resource()
  r.readEntries()
  r.dumpEntries()
