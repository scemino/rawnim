const
    BITS* = 16
    MASK = (1 shl BITS) - 1

type Frac* = object
    inc*: uint32
    offset*: uint64

proc getInt*(self: Frac): uint32 =
    (self.offset.int shr BITS).uint32

proc getFrac(self: Frac) : uint32 =
    (self.offset and MASK).uint32
    
proc interpolate*(self: Frac, sample1, sample2: int) : int =
    let fp = self.getFrac()
    (sample1 * (MASK - fp).int + sample2 * fp.int) shr BITS
