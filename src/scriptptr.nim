import ptrmath

type ScriptPtr* = object
    pc*: ptr byte
    byteSwap*: bool 

proc READ_LE_UINT16(p: ptr byte): uint16 =
    (p[1] shl 8) or p[0]

proc READ_BE_UINT16(p: ptr byte): uint16 =
    (p[0] shl 8) or p[1]
    
proc fetchByte*(self: var ScriptPtr): byte =
    result = self.pc[]
    self.pc += 1

proc fetchWord*(self: var ScriptPtr): uint16 =
    let i = if self.byteSwap: READ_LE_UINT16(self.pc) else: READ_BE_UINT16(self.pc)
    self.pc += 2
    return i.uint16
