import std/[endians, streams]

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

when isMainModule:
    echo system.cpuEndian
    var i = 0X12345678.uint32
    var o = swapEndian32(i)
    assert o == 0x78563412
    var p = cast[ptr byte](addr i)
    var o2 = swapEndian32(p)
    assert o2 == 0x78563412
