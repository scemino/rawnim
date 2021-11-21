import resource

when isMainModule:
  var r = Resource()
  r.readEntries()
  r.dumpEntries()