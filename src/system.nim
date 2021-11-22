type 
    System* = object
        pi*: PlayerInput
    PlayerInput* = object
        quit*: bool

proc getTimeStamp*(self: System): uint32 =
    discard

proc sleep*(self: System, duration: uint32) =
    discard
