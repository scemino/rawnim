import std/[logging, strformat]
import resource
import ptrmath
import frac
import scriptptr
import util

const
    NUM_CHANNELS = 4

type
    SfxInstrument = object
        data: ptr byte
        volume: uint16
    SfxModule = object
        data: ptr byte
        curPos: uint16
        curOrder: byte
        numOrder: byte
        orderTable: array[0x80, byte]
        samples: array[15, SfxInstrument]
    SfxPattern = object
        note_1: uint16
        note_2: uint16
        sampleStart: uint16
        sampleBuffer: ptr byte
        sampleLen: uint16
        loopPos: uint16
        loopLen: uint16
        sampleVolume: uint16
    SfxChannel = object
        sampleData: ptr byte
        sampleLen: uint16
        sampleLoopPos: uint16
        sampleLoopLen: uint16
        volume: uint16
        pos: Frac
    SfxPlayer* = ref SfxPlayerObj
    SfxPlayerObj = object
        res*: Resource
        delay: uint16
        resNum: uint16
        sfxMod: SfxModule
        syncVar*: ptr int16
        playing: bool
        rate: int
        samplesLeft: int
        channels: array[NUM_CHANNELS, SfxChannel]

var 
    prevL = 0
    prevR = 0

proc start*(self: var SfxPlayer) =
    debug(DBG_SND, "SfxPlayer::start()")
    self.sfxMod.curPos = 0

proc stop*(self: var SfxPlayer) =
    debug(DBG_SND, "SfxPlayer::stop()")
    self.playing = false
    self.resNum = 0

proc play*(self: var SfxPlayer, rate: int) =
    self.playing = true
    self.rate = rate
    self.samplesLeft = 0
    zeroMem(addr self.channels[0], sizeof(self.channels))

proc handlePattern(self: var SfxPlayer, channel: int, data: ptr byte) =
    var pat: SfxPattern
    pat.note_1 = READ_BE_UINT16(data + 0)
    pat.note_2 = READ_BE_UINT16(data + 2)
    if pat.note_1 != 0xFFFD:
        let sample = (pat.note_2 and 0xF000) shr 12
        if sample != 0:
            var p = self.sfxMod.samples[sample - 1].data
            if p != nil:
                # debug(DBG_SND, &"SfxPlayer::handlePattern() preparing sample {sample}")
                echo &"SfxPlayer::handlePattern() preparing sample {sample}"
                pat.sampleVolume = self.sfxMod.samples[sample - 1].volume
                pat.sampleStart = 8
                pat.sampleBuffer = p
                pat.sampleLen = READ_BE_UINT16(p) * 2
                let loopLen = READ_BE_UINT16(p + 2) * 2
                if loopLen != 0:
                    pat.loopPos = pat.sampleLen
                    pat.loopLen = loopLen
                else:
                    pat.loopPos = 0
                    pat.loopLen = 0
                var m = pat.sampleVolume.int16
                let effect = cast[byte]((pat.note_2 and 0x0F00) shr 8)
                if effect == 5: # volume up
                    var volume = cast[byte](pat.note_2 and 0xFF)
                    m += volume.int16
                    if m > 0x3F:
                        m = 0x3F
                elif effect == 6: # volume down
                    var volume = cast[byte](pat.note_2 and 0xFF)
                    m -= volume.int16
                    if m < 0:
                        m = 0
                self.channels[channel].volume = m.uint16
                pat.sampleVolume = m.uint16
    if pat.note_1 == 0xFFFD:
        # debug(DBG_SND, &"SfxPlayer::handlePattern() self.scriptVars[0xF4] = 0x{pat.note_2:X}")
        echo &"SfxPlayer::handlePattern() self.scriptVars[0xF4] = 0x{pat.note_2:X}"
        self.syncVar[] = cast[int16](pat.note_2)
    elif pat.note_1 != 0:
        if pat.note_1 == 0xFFFE:
            self.channels[channel].sampleLen = 0
        elif pat.sampleBuffer != nil:
            assert(pat.note_1 >= 0x37 and pat.note_1 < 0x1000)
            # convert amiga period value to hz
            let freq = (7159092 div (pat.note_1.int * 2)).uint16
            # debug(DBG_SND, &"SfxPlayer::handlePattern() adding sample freq = 0x{freq:X}")
            echo &"SfxPlayer::handlePattern() adding sample freq = 0x{freq:X}"
            var ch = addr self.channels[channel]
            ch.sampleData = pat.sampleBuffer + pat.sampleStart.int
            ch.sampleLen = pat.sampleLen
            ch.sampleLoopPos = pat.loopPos
            ch.sampleLoopLen = pat.loopLen
            ch.volume = pat.sampleVolume
            ch.pos.offset = 0
            ch.pos.inc = ((freq.int shl BITS) div self.rate).uint32

proc handleEvents(self: var SfxPlayer) =
    var order = self.sfxMod.orderTable[self.sfxMod.curOrder]
    var patternData = self.sfxMod.data + self.sfxMod.curPos.int + order.int * 1024
    for ch in 0..<4:
        self.handlePattern(ch, patternData)
        patternData += 4
    self.sfxMod.curPos += (4 * 4)
    #debug(DBG_SND, &"SfxPlayer::handleEvents() order = 0x{order:X} curPos = 0x{self.sfxMod.curPos:X}")
    echo &"SfxPlayer::handleEvents() order = 0x{order:X} curPos = 0x{self.sfxMod.curPos:X}"
    if self.sfxMod.curPos >= 1024:
        self.sfxMod.curPos = 0
        order = self.sfxMod.curOrder + 1
        if order == self.sfxMod.numOrder:
            self.resNum = 0
            self.playing = false
        self.sfxMod.curOrder = order

proc mixChannel(s: var int8, ch: var SfxChannel) =
    if ch.sampleLen != 0:
        var pos1 = cast[int](ch.pos.offset shr BITS)
        ch.pos.offset = ch.pos.offset + ch.pos.inc.uint64
        var pos2 = pos1 + 1
        if ch.sampleLoopLen != 0:
            if pos1 == ch.sampleLoopPos.int + ch.sampleLoopLen.int - 1:
                pos2 = ch.sampleLoopPos.int
                ch.pos.offset = cast[uint64](pos2 shl BITS)
        else:
            if pos1 == ch.sampleLen.int - 1:
                ch.sampleLen = 0
                return
        var sample = ch.pos.interpolate(cast[int8](ch.sampleData[pos1]), cast[int8](ch.sampleData[pos2])).int
        sample = s + sample * ch.volume.int div 64
        sample = clamp(sample, -128, 127)
        s = cast[int8](sample)

proc mixSamples(self: var SfxPlayer, buffer: ptr int8, l: int) =
    var buf = buffer
    var len = l
    zeroMem(buffer, len*2)
    let samplesPerTick = self.rate div (1000 div self.delay.int)
    while len != 0:
        if self.samplesLeft == 0:
            self.handleEvents()
            self.samplesLeft = samplesPerTick
        var count = self.samplesLeft
        if count > len:
            count = len
        self.samplesLeft -= count
        len -= count
        for i in 0..<count:
            mixChannel(buf[0], self.channels[0])
            mixChannel(buf[0], self.channels[3])
            buf += 1
            mixChannel(buf[0], self.channels[1])
            mixChannel(buf[0], self.channels[2])
            buf += 1

proc nr(inp: ptr int8, len: int, oup: ptr int8) =
    var input = inp
    var output = oup
    for i in 0..<len:
        let sL = cast[int](input[] shr 1)
        input += 1
        output[] = cast[int8](sL + prevL)
        output += 1
        prevL = sL
        let sR = cast[int](input[] shr 1)
        input += 1
        output[] = cast[int8](sR + prevR)
        output += 1
        prevR = sR

proc readSamples*(self: var SfxPlayer, buf: ptr int8, len: int) =
    if self.delay == 0:
        zeroMem(buf, len*2)
    else:
        let bufin = cast[ptr int8](alloc(len * 2))
        self.mixSamples(bufin, len)
        nr(bufin, len, buf)
        dealloc(bufin)

proc setEventsDelay*(self: var SfxPlayer, delay: uint16) =
    debug(DBG_SND, &"SfxPlayer::setEventsDelay({delay})")
    self.delay = (delay.int * 60 div 7050).uint16

proc prepareInstruments(self: var SfxPlayer, data: ptr byte) =
    zeroMem(addr self.sfxMod.samples[0], sizeof(self.sfxMod.samples))
    var p = data
    var i = 0
    for ins in self.sfxMod.samples.mitems:
        let resNum = READ_BE_UINT16(p)
        p += 2
        if resNum != 0:
            ins.volume = READ_BE_UINT16(p)
            var me = addr self.res.memList[resNum]
            if me.status == STATUS_LOADED and me.entryType == 0:
                ins.data = me.bufPtr
                debug(DBG_SND, &"Loaded instrument 0x{resNum:X} n={i} volume={ins.volume}")
            else:
                error(&"Error loading instrument 0x{resNum:X}")
        p += 2 # skip volume
        inc i

proc loadSfxModule*(self: var SfxPlayer, resNum, delay: uint16, pos: byte) =
    debug(DBG_SND, &"SfxPlayer::loadSfxModule(0x{resNum:X}, {delay}, {pos})")
    var me = self.res.memList[resNum].addr
    if me.status == STATUS_LOADED and me.entryType == 1:
        self.resNum = resNum
        zeroMem(addr self.sfxMod, sizeof(SfxModule))
        self.sfxMod.curOrder = pos
        self.sfxMod.numOrder = cast[byte](READ_BE_UINT16(me.bufPtr + 0x3E)) # TODO: check why this is a byte ?
        debug(DBG_SND, &"SfxPlayer::loadSfxModule() curOrder = 0x{self.sfxMod.curOrder:X} numOrder = 0x{self.sfxMod.numOrder:X}")
        copyMem(addr self.sfxMod.orderTable[0], addr me.bufPtr[0x40], 0x80)
        if delay == 0:
            self.delay = READ_BE_UINT16(me.bufPtr)
        else:
            self.delay = delay
        self.delay = (self.delay.int * 60 div 7050).uint16
        self.sfxMod.data = me.bufPtr + 0xC0
        debug(DBG_SND, &"SfxPlayer::loadSfxModule() eventDelay = {self.delay} ms")
        self.prepareInstruments(me.bufPtr + 2)
    else:
        warn "SfxPlayer::loadSfxModule() ec=0xF8"