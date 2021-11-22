type
    FixupPalette* = enum
        FIXUP_PALETTE_NONE,
        FIXUP_PALETTE_REDRAW # redraw all primitives on setPal script call
    Graphics* = object
        fixUpPalette*: FixupPalette