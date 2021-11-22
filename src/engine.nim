import resource
import script
import video
import graphics
from std/sugar import dup 

type
    Engine* = object
        graphics: Graphics
        script*: Script
        res*: ref Resource
        vid: Video
        partNum: int

const restartPos: array[36 * 2, int] = [
        16008,  0, 16001,  0, 16002, 10, 16002, 12, 16002, 14,
        16003, 20, 16003, 24, 16003, 26, 16004, 30, 16004, 31,
        16004, 32, 16004, 33, 16004, 34, 16004, 35, 16004, 36,
        16004, 37, 16004, 38, 16004, 39, 16004, 40, 16004, 41,
        16004, 42, 16004, 43, 16004, 44, 16004, 45, 16004, 46,
        16004, 47, 16004, 48, 16004, 49, 16006, 64, 16006, 65,
        16006, 66, 16006, 67, 16006, 68, 16005, 50, 16006, 60,
        16007, 0
    ]

proc newEngine*(partNum: int) : Engine =
    var res = new(Resource)
    result = Engine(partNum: partNum, res: res)
    result.script = Script(res: res)

proc setup*(self: var Engine) =
    self.vid.graphics = self.graphics
    self.vid.init()
    self.res[].allocMemBlock()
    self.res[].readEntries()
    #self.res.dumpEntries()
    self.script.init()
    let num = self.partNum
    if num < 36:
        self.script.restartAt(restartPos[num * 2], restartPos[num * 2 + 1])
    else:
        self.script.restartAt(num)

proc processInput(self: var Engine) =
    # TODO
    # if self.sys.pi.fastMode:
    #     self.script.fastMode = !self.script.fastMode
    #     self.sys.pi.fastMode = false
    # if self.sys.pi.screenshot:
    #     self.vid.captureDisplay()
    #     self.sys.pi.screenshot = false
    discard

proc finish*(self: var Engine) =
    discard
    # TODO:
    # self.graphics.fini()
    # self.ply.stop()
    # self.mix.quit()
    # self.res.freeMemBlock()

proc run*(self: var Engine) =
    self.script.setupTasks()
    self.script.updateInput()
    self.processInput()
    self.script.runTasks()
    #self.mix.update()
