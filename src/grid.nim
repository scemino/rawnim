type
    Grid*[N1, N2: static[int], T] = array[N1*N2, T]

proc `[]`*[N1, N2, T](g: var Grid[N1, N2, T], x, y: int): T =
    result = g[y*N1+x]

proc `[]=`*[N1, N2, T](g: var Grid[N1, N2, T], x, y: int, value: T) =
    g[y*N1+x] = value
