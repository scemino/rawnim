# from https://forum.nim-lang.org/t/1188#7366 by Jehan
# most of the time only the dereference operator is needed, import it like this:
# from ptrmath import `[]`

template `+`*[T](p: ptr T, off: int): ptr T =
  cast[ptr type(p[])](cast[ByteAddress](p) +% off * sizeof(p[]))

template `+=`*[T](p: ptr T, off: int) =
  p = p + off

template `-`*[T](p: ptr T, off: int): ptr T =
  cast[ptr type(p[])](cast[ByteAddress](p) -% off * sizeof(p[]))

template `-=`*[T](p: ptr T, off: int) =
  p = p - off

template `[]`*[T](p: ptr T, off: int): T =
  (p + off)[]

template `[]=`*[T](p: ptr T, off: int, val: T) =
  (p + off)[] = val
  
when isMainModule:
  var a: array[0..3, int]
  for i in a.low..a.high:
    a[i] += i
  var p = addr(a[0])
  p += 1
  p[0] -= 2
  echo p[0], " ", p[1]
