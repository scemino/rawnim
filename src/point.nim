type Point* = object
    x*, y*: int16

proc newPoint*(): Point = 
    result = Point()

proc newPoint*(xx, yy: int16): Point = 
    result = Point(x: xx, y: yy)

proc newPoint*(p: Point): Point =
    result = Point(x: p.x, y: p.y)

proc scale*(self: var Point, u, v: int) =
    self.x = ((self.x * u).int shr 16).int16
    self.y = ((self.y * v).int shr 16).int16
