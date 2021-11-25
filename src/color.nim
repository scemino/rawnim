type Color* = object
    r*,g*,b*: range[0..255]

proc rgb555*(self: Color): uint16 =
    result = (((self.r shr 3) shl 10) or ((self.g shr 3) shl 5) or (self.b shr 3)).uint16
