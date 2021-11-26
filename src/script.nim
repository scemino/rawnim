import std/[algorithm, logging, strformat]
import parts
import resource
import grid
import system
import scriptptr
import ptrmath
import video
import util
import graphics
import point
import parts

type
    ScriptVars = enum
        svRandomSeed = 0x3C, svScreenNum = 0x67, svLastKeyChar = 0xDA, svHeroPosUpDown = 0xE5, svMusicSync =0xF4, svScrollY = 0xF9,
        svHeroAction = 0xFA, svHeroPosJumpDown = 0xFB, svHeroPosLeftRight  = 0xFC, svHeroPosMask = 0xFD, svHeroActionPosMask = 0xFE, svPauseSlices = 0xFF
    Script* = object
        res: Resource
        vid: Video
        sys*: System
        scriptVars: array[256, int16]
        scriptStackCalls: array[64, uint16]
        scriptTasks: Grid[2, 64, uint16]
        scriptStates: Grid[2, 64, uint16]
        scriptPtr: ScriptPtr
        stackPtr: byte
        scriptPaused: bool
        fastMode: bool
        screenNum: int
        startTime, timeStamp: uint32
        fastMode: bool

proc newScript*(res: Resource, vid: Video): Script =
    result = Script(res: res, vid: vid)

proc init*(self: var Script) =
    self.scriptVars.fill(0)
    self.fastMode = false
    #TODO: self.ply.syncVar = &self.scriptVars[svMusicSync.int]
    self.scriptPtr.byteSwap = false
    
    self.scriptVars[svRandomSeed.int] = 0 #time(0)
#ifdef BYPASS_PROTECTION
    # these 3 variables are set by the game code
    self.scriptVars[0xBC] = 0x10
    self.scriptVars[0xC6] = 0x80
    self.scriptVars[0xF2] = 4000
    # these 2 variables are set by the engine executable
    self.scriptVars[0xDC] = 33
#endif
    self.scriptVars[0xE4] = 20

proc updateInput*(self: var Script) =
    self.sys.processEvents()
    if self.res.currentPart == kPartPassword.uint16:
        var c = self.sys.pi.lastChar
        if c == cast[char](8) or c == cast[char](0) or (c >= 'a' and c <= 'z'):
            self.scriptVars[svLastKeyChar.int] = cast[int16](cast[int](c) and not 0x20)
            self.sys.pi.lastChar = cast[char](0)
    var lr, m, ud, jd: int16
    if self.sys.pi.dirMask.contains(DIR_RIGHT):
        lr = 1
        m = m or 1
    if self.sys.pi.dirMask.contains(DIR_LEFT):
        lr = -1
        m = m or 2
    if self.sys.pi.dirMask.contains(DIR_DOWN):
        ud = 1
        jd = 1
        m = m or 4 # crouch
    if self.sys.pi.dirMask.contains(DIR_UP):
        ud = -1
        jd = -1
        m = m or 8 # jump
    self.scriptVars[svHeroPosUpDown.int] = ud
    self.scriptVars[svHeroPosJumpDown.int] = jd
    self.scriptVars[svHeroPosLeftRight.int] = lr
    self.scriptVars[svHeroPosMask.int] = m
    var action = 0.int16
    if self.sys.pi.action:
        action = 1
        m = m or 0x80
    self.scriptVars[svHeroAction.int] = action
    self.scriptVars[svHeroActionPosMask.int] = m

proc inp_handleSpecialKeys*(self: var Script) =
    if self.sys.pi.pause:
        if self.res.currentPart != kPartCopyProtection.uint16 and self.res.currentPart != kPartIntro.uint16:
            self.sys.pi.pause = false;
            while not self.sys.pi.pause and not self.sys.pi.quit:
                self.sys.processEvents()
                self.sys.sleep(50);
        self.sys.pi.pause = false

    if self.sys.pi.code:
        self.sys.pi.code = false
        if self.res.hasPasswordScreen:
            if self.res.currentPart != kPartPassword.uint16 and self.res.currentPart != kPartCopyProtection.uint16:
                self.res.nextPart = kPartPassword.uint16

proc fixUpPalette_changeScreen(self: var Script, part, screen: int) =
    var pal = -1
    case part:
    of 16004:
        if screen == 0x47: # bitmap resource #68
            pal = 8
    of 16006:
        if screen == 0x4A: # bitmap resources #144, #145
            pal = 1
    else: 
        discard
    if pal != -1:
        debug(DBG_SCRIPT, &"Setting palette {pal} for part {part} screen {screen}")
        self.vid.changePal(self.res.segVideoPal, pal.byte)

proc snd_playSound(self: Script, resNum: uint16, freq, vol, channel: uint8) =
    discard

proc snd_playMusic(self: Script, resNum, delay: uint16, pos: byte) =
    discard

{.push overflowchecks: off.}
proc op_movConst(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var n = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_movConst(0x{i:02X}, {n})")
    self.scriptVars[i] = cast[int16](n)

proc op_mov(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var j = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_mov(0x{i:02X}, 0x{j:02X})")
    self.scriptVars[i] = self.scriptVars[j]

proc op_add(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var j = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_add(0x{i:02X}, 0x{j:02X})")
    self.scriptVars[i] += self.scriptVars[j]

proc op_addConst(self: var Script) =
    if self.res.currentPart == 16006 and self.scriptPtr.pc == self.res.segCode + 0x6D48:
        warn "Script::op_addConst() workaround for infinite looping gun sound"
        # The script 0x27 slot 0x17 doesn't stop the gun sound from looping.
        # This is a bug in the original game code, confirmed by Eric Chahi and
        # addressed with the anniversary editions.
        # For older releases (DOS, Amiga), we play the 'stop' sound like it is
        # done in other part of the game code.
        #
        #  6D43: jmp(0x6CE5)
        #  6D46: break
        #  6D47: VAR(0x06) -= 50
        #
        self.snd_playSound(0x5B, 1, 64, 1)
    var i = self.scriptPtr.fetchByte()
    var n = cast[int16](self.scriptPtr.fetchWord())
    debug(DBG_SCRIPT, &"Script::op_addConst(0x{i:02X}, {n})")
    self.scriptVars[i] += n

proc op_call(self: var Script) =
    let off = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_call(0x{off:02X})")
    if self.stackPtr == 0x40:
        error "Script::op_call() ec=0x8F stack overflow"
    self.scriptStackCalls[self.stackPtr] = cast[uint16](self.scriptPtr.pc) - cast[uint16](self.res.segCode)
    self.stackPtr += 1
    self.scriptPtr.pc = self.res.segCode + off.int

proc op_ret(self: var Script) =
    debug(DBG_SCRIPT, "Script::op_ret()")
    if self.stackPtr == 0:
        error "Script::op_ret() ec=0x8F stack underflow"
    self.stackPtr -= 1
    self.scriptPtr.pc = self.res.segCode + self.scriptStackCalls[self.stackPtr.int].int

proc op_yieldTask(self: var Script) =
    debug(DBG_SCRIPT, "Script::op_yieldTask()")
    self.scriptPaused = true

proc op_jmp(self: var Script) =
    let off = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_jmp(0x{off:02X})")
    self.scriptPtr.pc = self.res.segCode + off.int

proc op_installTask(self: var Script) =
    let i = self.scriptPtr.fetchByte().int
    let n = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_installTask(0x{i:X}, 0x{n:04X})")
    assert(i < 0x40)
    self.scriptTasks[1,i] = n

proc op_jmpIfVar(self: var Script) =
    let i = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_jmpIfVar(0x{i:02X})")
    self.scriptVars[i] -= 1
    if self.scriptVars[i] != 0:
        self.op_jmp()
    else:
        discard self.scriptPtr.fetchWord()

proc op_condJmp(self: var Script) =
    let op = self.scriptPtr.fetchByte()
    let variable = self.scriptPtr.fetchByte()
    let b = self.scriptVars[variable]
    var a : int16
    if (op and 0x80) != 0:
        a = self.scriptVars[self.scriptPtr.fetchByte().int]
    elif (op and 0x40) != 0:
        a = cast[int16](self.scriptPtr.fetchWord())
    else:
        a = cast[int16](self.scriptPtr.fetchByte())
    debug(DBG_SCRIPT, &"Script::op_condJmp({op:02X}, 0x{b:02X}, 0x{a:02X}) var=0x{variable:02X}")
    var expression = false
    case (op and 7):
    of 0:
        expression = (b == a)
# BYPASS_PROTECTION
        if self.res.currentPart == kPartCopyProtection.uint16:
            #
            # 0CB8: jmpIf(VAR(0x29) == VAR(0x1E), @0CD3)
            # ...
            #
            if variable == 0x29 and (op and 0x80) != 0:
                # 4 symbols
                self.scriptVars[0x29] = self.scriptVars[0x1E]
                self.scriptVars[0x2A] = self.scriptVars[0x1F]
                self.scriptVars[0x2B] = self.scriptVars[0x20]
                self.scriptVars[0x2C] = self.scriptVars[0x21]
                # counters
                self.scriptVars[0x32] = 6
                self.scriptVars[0x64] = 20
                warn "Script::op_condJmp() bypassing protection"
                expression = true
    of 1:
        expression = (b != a)
    of 2:
        expression = (b > a)
    of 3:
        expression = (b >= a)
    of 4:
        expression = (b < a)
    of 5:
        expression = (b <= a)
    else:
        warn &"Script::op_condJmp() invalid condition {op and 7}"
    if expression:
        self.op_jmp()
        if variable == svScreenNum.byte and self.screenNum != self.scriptVars[svScreenNum.int]:
            self.fixUpPalette_changeScreen(self.res.currentPart.int, self.scriptVars[svScreenNum.int].int)
            self.screenNum = self.scriptVars[svScreenNum.int]
    else:
        discard self.scriptPtr.fetchWord()

proc op_setPalette(self: var Script) =
    let i = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_changePalette({i})")
    let num = i shr 8
    if self.vid.graphics.fixUpPalette == FIXUP_PALETTE_REDRAW:
        if self.res.currentPart == 16001:
            if (num == 10 or num == 16):
                return
        self.vid.nextPal = num.byte
    else:
        self.vid.nextPal = num.byte

proc op_changeTasksState(self: var Script) =
    var start = self.scriptPtr.fetchByte()
    var stop = self.scriptPtr.fetchByte()
    if stop < start:
        warn "Script::op_changeTasksState() ec=0x880 (stop < start)"
        return
    var state = self.scriptPtr.fetchByte()

    debug(DBG_SCRIPT, &"Script::op_changeTasksState({start}, {stop}, {state})")

    if state == 2.byte:
        for i in start..stop:
            self.scriptTasks[1,i.int] = 0xFFFE
    elif state < 2:
        for i in start..stop:
            self.scriptStates[1,i.int] = state

proc op_selectPage(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_selectPage({i})")
    self.vid.setWorkPagePtr(i)

proc op_fillPage(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var color = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_fillPage({i}, {color})")
    self.vid.fillPage(i, color)

proc op_copyPage(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var j = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_copyPage({i}, {j})")
    self.vid.copyPage(i, j, self.scriptVars[svScrollY.int])

proc op_updateDisplay(self: var Script) =
    var page = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_updateDisplay({page})")
    self.inp_handleSpecialKeys()

# TODO:
#ifndef BYPASS_PROTECTION
    # // entered protection symbols match the expected values
    # if (_res._currentPart == 16000 && _scriptVars[0x67] == 1) {
    # 	_scriptVars[0xDC] = 33
    # }
#endif

    const frameHz = 50
    if not self.fastMode and self.scriptVars[svPauseSlices.int] != 0.int16:
        let delay = self.sys.getTimeStamp() - self.timeStamp
        let pause = self.scriptVars[svPauseSlices.int] * 1000 div frameHz - delay.int
        if pause > 0:
            self.sys.sleep(pause.uint32)

    self.timeStamp = self.sys.getTimeStamp()
    self.scriptVars[0xF7] = 0

    self.vid.displayHead = not ((self.res.currentPart == 16004 and self.screenNum == 37) or (self.res.currentPart == 16006 and self.screenNum == 202))
    self.vid.updateDisplay(self.res.segVideoPal, page, self.sys)

proc op_removeTask(self: var Script) =
    debug(DBG_SCRIPT, "Script::op_removeTask()")
    self.scriptPtr.pc = self.res.segCode + 0xFFFF
    self.scriptPaused = true

proc op_drawString(self: var Script) =
    var strId = self.scriptPtr.fetchWord()
    var x = self.scriptPtr.fetchByte()
    var y = self.scriptPtr.fetchByte()
    var col = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_drawString(0x{strId:03X}, {x}, {y}, {col})")
    self.vid.drawString(col, x, y, strId)

proc op_sub(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var j = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_sub(0x{i:02X}, 0x{j:02X})")
    self.scriptVars[i] -= self.scriptVars[j]

proc op_and(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var n = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_and(0x{i:02X}, {n})")
    self.scriptVars[i] = self.scriptVars[i].int16 and n.int16

proc op_or(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var n = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_or(0x{i:02X}, {n})")
    self.scriptVars[i] = self.scriptVars[i].int16 or n.int16

proc op_shl(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var n = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_shl(0x{i:02X}, {n})")
    self.scriptVars[i] = self.scriptVars[i].int16 shl n.int16

proc op_shr(self: var Script) =
    var i = self.scriptPtr.fetchByte()
    var n = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_shr(0x{i:02X}, {n})")
    self.scriptVars[i] = self.scriptVars[i].int16 shr n.int16

proc op_playSound(self: var Script) =
    var resNum = self.scriptPtr.fetchWord()
    var freq = self.scriptPtr.fetchByte()
    var vol = self.scriptPtr.fetchByte()
    var channel = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_playSound(0x{resNum:X}, {freq}, {vol}, {channel})")
    self.snd_playSound(resNum, freq, vol, channel)

proc op_updateResources(self: var Script) =
    var num = self.scriptPtr.fetchWord()
    debug(DBG_SCRIPT, &"Script::op_updateResources({num})")
    if num == 0:
        #self.ply.stop()
        #self.mix.stopAll()
        self.res.invalidateRes()
    else:
        self.res.update(num)

proc op_playMusic(self: var Script) =
    var resNum = self.scriptPtr.fetchWord()
    var delay = self.scriptPtr.fetchWord()
    var pos = self.scriptPtr.fetchByte()
    debug(DBG_SCRIPT, &"Script::op_playMusic(0x{resNum:X}, {delay}, {pos})")
    self.snd_playMusic(resNum, delay, pos)
{.pop.}

const 
    opTable = [
        # 0x00
        op_movConst, op_mov, op_add, op_addConst,
        # 0x04
        op_call, op_ret, op_yieldTask, op_jmp,
        # 0x08
        op_installTask, op_jmpIfVar, op_condJmp, op_setPalette,
        # 0x0C
        op_changeTasksState, op_selectPage, op_fillPage, op_copyPage,
        # 0x10
        op_updateDisplay, op_removeTask, op_drawString, op_sub,
        # 0x14
        op_and, op_or, op_shl, op_shr,
        # 0x18
        op_playSound, op_updateResources, op_playMusic
    ]

proc restartAt*(self: var Script, part, pos: int = -1) =
    if part == kPartCopyProtection.int:
        # VAR(0x54) indicates if the "Out of this World" title screen should be presented
        #
        #   0084: jmpIf(VAR(0x54) < 128, @00C4)
        #   ..
        #   008D: setPalette(num=0)
        #   0090: updateResources(res=18)
        #   ...
        #   00C4: setPalette(num=23)
        #   00CA: updateResources(res=71)

        # Use "Another World" title screen if language is set to French
        self.scriptVars[0x54] = 0x1  #: 0x81
    self.res.setupPart(part)
    self.scriptTasks.fill(0xFFFF.uint16)
    self.scriptStates.fill(0)
    self.scriptTasks[0,0] = 0.uint16
    self.screenNum = -1
    if pos >= 0:
        self.scriptVars[0] = pos.int16
    self.startTime = self.sys.getTimeStamp()
    self.timeStamp = self.startTime
    # TODO: if part == kPartWater.int:
    #     if self.res.demo3Joy.start():
    #         self.scriptVars.fill(0)

proc setupTasks*(self: var Script) =
    if self.res.nextPart != 0:
        self.restartAt(self.res.nextPart.int)
        self.res.nextPart = 0
    for i in 0..<0x40:
        self.scriptStates[0,i] = self.scriptStates[1,i]
        var n = self.scriptTasks[1,i]
        if n != 0xFFFF:
            self.scriptTasks[0,i] = if n == 0xFFFE: 0xFFFF else: n.int
            self.scriptTasks[1,i] = 0xFFFF

proc executeTask(self: var Script) =
    while not self.scriptPaused:
        var opcode = self.scriptPtr.fetchByte()
        if (opcode and 0x80) != 0:
            let off = ((opcode.uint16 shl 8) or self.scriptPtr.fetchByte()) shl 1
            self.res.useSegVideo2 = false
            var pt = newPoint(self.scriptPtr.fetchByte().int16, self.scriptPtr.fetchByte().int16)
            var h = pt.y - 199.int16
            if h > 0:
                pt.y = 199
                pt.x += h
            debug(DBG_VIDEO, &"vid_opcd_0x80 : opcode=0x{opcode:X} off=0x{off:X} x={pt.x} y={pt.y}")
            self.vid.setDataBuffer(self.res.segVideo1, off)
            self.vid.drawShape(0xFF, 64, pt)
        elif (opcode and 0x40) != 0:
            var pt = newPoint()
            let offsetHi = self.scriptPtr.fetchByte()
            let off = ((offsetHi.uint16 shl 8) or self.scriptPtr.fetchByte()) shl 1
            pt.x = self.scriptPtr.fetchByte().int16
            self.res.useSegVideo2 = false
            if (opcode and 0x20) == 0:
                if (opcode and 0x10) == 0:
                    pt.x = (pt.x shl 8) or self.scriptPtr.fetchByte().int16
                else:
                    pt.x = self.scriptVars[pt.x]
            else:
                if (opcode and 0x10) != 0:
                    pt.x += 0x100
            pt.y = self.scriptPtr.fetchByte().int16
            if (opcode and 8) == 0:
                if (opcode and 4) == 0:
                    pt.y = (pt.y shl 8) or self.scriptPtr.fetchByte().int16
                else:
                    pt.y = self.scriptVars[pt.y]
            var zoom = 64
            if (opcode and 2) == 0:
                if (opcode and 1) != 0:
                    zoom = self.scriptVars[self.scriptPtr.fetchByte()]
            else:
                if (opcode and 1) != 0:
                    self.res.useSegVideo2 = true
                else:
                    zoom = self.scriptPtr.fetchByte().int
            debug(DBG_VIDEO, &"vid_opcd_0x40 : off=0x{off:X} x={pt.x} y={pt.y}")
            self.vid.setDataBuffer(if self.res.useSegVideo2: self.res.segVideo2 else: self.res.segVideo1, off)
            self.vid.drawShape(0xFF, zoom.uint16, pt)
        else:
            if opcode > 0x1A:
                discard
                error &"Script::executeTask() ec=0xFFF invalid opcode=0x{opcode:X}"
            else:
                opTable[opcode](self)

proc runTasks*(self: var Script) =
    for i in 0..<0x40:
        if self.sys.pi.quit:
            return
        if self.scriptStates[0, i] == 0:
            var n = self.scriptTasks[0,i]
            if n != 0xFFFF:
                self.scriptPtr.pc = self.res.segCode + n.int
                self.stackPtr = 0
                self.scriptPaused = false
                debug(DBG_SCRIPT, &"Script::runTasks() i=0x{i:02X} n=0x{n:04X}")
                self.executeTask()
                self.scriptTasks[0,i] = cast[uint16](self.scriptPtr.pc) - cast[uint16](self.res.segCode)
                debug(DBG_SCRIPT, &"Script::runTasks() i=0x{i:02X} pos=0x{self.scriptTasks[0,i]:X}")