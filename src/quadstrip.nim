import point

const MAX_VERTICES = 70

type QuadStrip* = object
    numVertices*: byte
    vertices*: array[MAX_VERTICES, Point]
