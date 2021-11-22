import std/[endians, streams, logging]

type 
    ChannelMask* = enum
        DBG_SCRIPT = 1 shl 0,
        DBG_BANK  = 1 shl 1,
        DBG_VIDEO = 1 shl 2,
        DBG_SND   = 1 shl 3,
        DBG_SER   = 1 shl 4,
        DBG_INFO  = 1 shl 5,
        DBG_PAK   = 1 shl 6,
        DBG_RESOURCE = 1 shl 7
var g_debugMask*: set[ChannelMask]

proc swapEndian32*(src: uint32): uint32 =
    var dst : uint32
    swapEndian32(addr dst, unsafeAddr src)
    result = dst

proc swapEndian32*(p: ptr byte): uint32 =
    var dst : uint32
    swapEndian32(addr dst, p)
    result = dst

proc readUint32BE*(s: Stream): uint32 =
  result = swapEndian32(s.readUint32())

template debug*(cm: ChannelMask, args: varargs[string, `$`]) =
    if g_debugMask.contains(cm):
        debug(args)

when isMainModule:
    echo system.cpuEndian
    var i = 0X12345678.uint32
    var o = swapEndian32(i)
    assert o == 0x78563412
    var p = cast[ptr byte](addr i)
    var o2 = swapEndian32(p)
    assert o2 == 0x78563412
