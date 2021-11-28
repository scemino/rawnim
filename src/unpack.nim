
import std/[logging, strformat]
import ptrmath
import util

type 
    UnpackCtx = object
        size: int
        crc: uint32
        bits: uint32
        dst: ptr byte
        src: ptr byte

proc nextBit(uc: var UnpackCtx): bool =
    result = (uc.bits and 1) != 0
    uc.bits = uc.bits shr 1
    if uc.bits == 0: # getnextlwd
        uc.bits = swapEndian32(uc.src)
        uc.src -= 4
        uc.crc = uc.crc xor uc.bits
        result = (uc.bits and 1) != 0
        uc.bits = (1 shl 31) or (uc.bits shr 1)

proc getBits(uc: var UnpackCtx, count: int): int = # rdd1bits
    var bits = 0
    for i in 0..<count:
        bits = bits shl 1
        if uc.nextBit():
            bits = bits or 1
    return bits

proc copyLiteral(uc: var UnpackCtx, bitsCount: int, len: int) = # getd3chr
    var count = uc.getBits(bitsCount) + len + 1
    uc.size -= count
    if uc.size < 0:
        count += uc.size
        uc.size = 0
    for i in 0..<count:
        uc.dst[-i] = getBits(uc, 8).byte
    uc.dst -= count

proc copyReference(uc: var UnpackCtx, bitsCount: int, c: int) = # copyd3bytes
    var count = c
    uc.size -= count
    if uc.size < 0:
        count += uc.size
        uc.size = 0
    let offset = getBits(uc, bitsCount)
    for i in 0..<count:
        uc.dst[-i] = uc.dst[-i + offset]
    uc.dst -= count

proc bytekiller_unpack*(dst: ptr byte, dstSize: int, src: ptr byte, srcSize: int) : bool =
    var uc = UnpackCtx()
    uc.src = src + srcSize - 4
    uc.size = swapEndian32(uc.src).int
    uc.src -= 4
    if uc.size > dstSize:
        info &"Warning: Unexpected unpack size {uc.size}, buffer size {dstSize}"
        return false
    uc.dst = dst + uc.size - 1
    uc.crc = swapEndian32(uc.src)
    uc.src -= 4
    uc.bits = swapEndian32(uc.src)
    uc.src -= 4
    uc.crc = uc.crc xor uc.bits
    while uc.size > 0:
        if not uc.nextBit():
            if not uc.nextBit():
                uc.copyLiteral(3, 0)
            else:
                uc.copyReference(8, 2)
        else:
            let code = uc.getBits(2)
            case code:
            of 3:
                uc.copyLiteral(8, 8)
            of 2:
                uc.copyReference(12, uc.getBits(8) + 1)
            of 1:
                uc.copyReference(10, 4)
            of 0:
                uc.copyReference(9, 3)
            else: 
                discard
    assert uc.size == 0
    return uc.crc == 0

