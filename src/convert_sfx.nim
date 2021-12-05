import std/[os, strformat, parseutils]
import ptrmath

const
    PAULA_FREQ = 3579545
    kHz = 22050
    kFracBits = 16
    NUM_CHANNELS = 4
    NUM_INSTRUMENTS = 15

proc READ_BE_UINT16(p: ptr byte):uint16 =
    p[0].uint16 shl 8 or p[1]

type
    InstrumentSample = object
        data: ptr byte
        len: int
        loopPos: int
        loopLen: int
    SfxInstrument = object
        resId: uint16
        volume: uint16
        buf: seq[byte]
    SfxModule = object
        buf: seq[byte]
        samples: array[NUM_INSTRUMENTS, SfxInstrument]
        curOrder, numOrder: byte
        orderTable: array[0x80, byte]
    Pattern = object
        note_1, note_2: uint16
        sample_start: uint16
        sample_buffer: ptr byte
        period_value: uint16
        loopPos: uint16
        loopData: ptr byte
        loopLen: uint16
        period_arpeggio: uint16 # unused by Another World tracks
        sample_volume: uint16
    Channel = object
        sample: InstrumentSample
        pos: uint32
        inc: uint64
        volume: int
    Player = object
        delay: uint16
        curPos: uint16
        bufData: ptr byte
        sfxMod: SfxModule
        patterns: array[4, Pattern]
        channels: array[NUM_CHANNELS, Channel]
        playingMusic: bool
        rate: int
        samplesLeft: int

proc readFile(filename: string) : seq[byte] =
    echo "filename=",filename
    var fp = open(filename)
    result = newSeq[byte](getFileSize(fp))
    discard fp.readBuffer(addr result[0], result.len)
    close(fp)

proc loadInstruments(self: var Player, data: ptr byte) =
    var p = data
    zeroMem(addr self.sfxMod.samples[0], sizeof(self.sfxMod.samples))
    var i = 0
    for ins in self.sfxMod.samples.mitems:
        ins.resId = READ_BE_UINT16(p)
        p += 2
        if ins.resId != 0:
            ins.volume = READ_BE_UINT16(p)
            let path = &"data/data_{ins.resId:02X}_0"
            ins.buf = readFile(path)
            zeroMem(addr ins.buf[8], 4)
            echo &"Loaded instrument '{path}' n={i} volume={ins.volume}"
        p += 2 # volume
        inc i

proc stop(elf: var Player) =
    discard

proc start(self: var Player) =
    self.curPos = 0
    self.playingMusic = true
    zeroMem(addr self.channels[0], sizeof(self.channels))
    self.rate = kHz
    self.samplesLeft = 0

proc loadSfxModule(self: var Player, num: int) =
    let path = &"data/data_{num:02X}_1"
    self.sfxMod.buf = readFile(path)
    var p = addr self.sfxMod.buf[0]
    self.sfxMod.curOrder = 0
    self.sfxMod.numOrder = READ_BE_UINT16(p + 0x3E).byte
    echo &"curOrder = 0x{self.sfxMod.curOrder:X} numOrder = 0x{self.sfxMod.numOrder:X}"
    for i in 0..<0x80:
        self.sfxMod.orderTable[i] = p[0x40 + i]
    self.delay = READ_BE_UINT16(p)
#		_delay = 15700
    self.delay = (self.delay.int * 60 div 7050).uint16
    self.bufData = p + 0xC0
    echo &"eventDelay = {self.delay}"
    self.loadInstruments(p + 2)
    self.stop()
    self.start()

proc Mix_setChannelVolume(self: var Player, channel, volume: int) =
    self.channels[channel].volume = volume

proc Mix_stopChannel(self: var Player, channel: int) =
    zeroMem(addr self.channels[channel], sizeof(Channel))


proc Mix_playChannel(self: var Player, channel: int, sample: var InstrumentSample, freq, volume: int) =
    self.channels[channel].sample = sample
    self.channels[channel].pos = 0
    self.channels[channel].inc = ((freq.int shl kFracBits) div self.rate).uint64
    self.channels[channel].volume = volume

proc handlePattern(self: var Player, channel: byte, data: var ptr byte, pat: var Pattern) =
    pat.note_1 = READ_BE_UINT16(data + 0)
    pat.note_2 = READ_BE_UINT16(data + 2)
    echo &"handlePattern {pat.note_1} {pat.note_2}"
    data += 4
    if pat.note_1 != 0xFFFD:
        var sample = (pat.note_2 and 0xF000) shr 12
        if sample != 0:
            var p = addr self.sfxMod.samples[sample - 1].buf[0]
            echo &"Preparing sample {sample}"
            if p != nil:
                pat.sample_volume = self.sfxMod.samples[sample - 1].volume
                pat.sample_start = 8
                pat.sample_buffer = p
                pat.period_value = READ_BE_UINT16(p) * 2
                var loopLen = READ_BE_UINT16(p + 2) * 2
                if loopLen != 0:
                    pat.loopPos = pat.period_value
                    pat.loopData = p
                    pat.loopLen = loopLen
                else:
                    pat.loopPos = 0
                    pat.loopData = nil
                    pat.loopLen = 0
                var m = pat.sample_volume
                let effect = ((pat.note_2 and 0x0F00) shr 8).byte
                echo &"pat->note_2 = {pat.note_2}"
                echo &"effect = {effect}"
                if effect == 5: # volume up
                    var volume = pat.note_2 and 0xFF
                    m += volume
                    if m > 0x3F:
                        m = 0x3F
                elif effect == 6: # volume down
                    var volume = (pat.note_2 and 0xFF)
                    m -= volume
                    if m < 0:
                        m = 0
                elif effect != 0:
                    echo &"Unhandled effect {effect}"
                self.Mix_setChannelVolume(channel.int, m.int)
                pat.sample_volume = m
    if pat.note_1 == 0xFFFD: # 'PIC'
        pat.note_2 = 0
    elif pat.note_1 != 0:
        pat.period_arpeggio = pat.note_1
        if pat.period_arpeggio == 0xFFFE:
            self.Mix_stopChannel(channel.int)
        elif pat.sample_buffer != nil:
            var sample: InstrumentSample
            zeroMem(addr sample, sizeof(InstrumentSample))
            sample.data = pat.sample_buffer + pat.sample_start.int
            sample.len = pat.period_value.int
            sample.loopPos = pat.loopPos.int
            sample.loopLen = pat.loopLen.int
            assert(pat.note_1 < 0x1000)
            var freq = PAULA_FREQ div pat.note_1
            echo &"Adding sample indFreq = {pat.note_1} freq = {freq}"
            self.Mix_playChannel(channel.int, sample, freq.int, pat.sample_volume.int)

proc Mix_stopAll(self: var Player) =
    zeroMem(addr self.channels[0], sizeof(self.channels))

proc handleEvents(self: var Player) =
    var order = self.sfxMod.orderTable[self.sfxMod.curOrder]
    var patternData = self.bufData + self.curPos.int + order.int * 1024
    zeroMem(addr self.patterns[0], sizeof(self.patterns))
    for ch in 0..<4:
        self.handlePattern(ch.byte, patternData, self.patterns[ch])
    self.curPos += 4 * 4
    echo &"order = 0x{order:X} curPos = 0x{self.curPos:X}"
    if self.curPos >= 1024:
        self.curPos = 0
        order = self.sfxMod.curOrder + 1
        if order == self.sfxMod.numOrder:
            self.Mix_stopAll()
            order = 0
            self.playingMusic = false
        self.sfxMod.curOrder = order

proc Mix_doMixChannel(self: var Player, buf: ptr int8, channel: int) =
    var sample = addr self.channels[channel].sample
    if sample.data == nil:
        return
    var pos = self.channels[channel].pos shr kFracBits
    self.channels[channel].pos += self.channels[channel].inc.uint32
    if sample.loopLen != 0:
        if pos == sample.loopPos.uint32 + sample.len.uint32 - 1:
            self.channels[channel].pos = sample.loopPos.uint32 shl kFracBits
    else:
        if pos == sample.len.uint32 - 1:
            sample.data = nil
            return
    var s = cast[int8](sample.data[pos.int]).int
    s = buf[] + s * self.channels[channel].volume div 64
    if s < -128:
        s = -128
    elif s > 127:
        s = 127
    buf[] = cast[int8](s)

proc Mix_doMix(self: var Player, buffer: ptr int8, length: int) =
    var buf = buffer
    var len = length
    zeroMem(buf, 2 * len)
    if self.delay != 0:
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
                self.Mix_doMixChannel(buf, 0);
                self.Mix_doMixChannel(buf, 3);
                buf += 1
                self.Mix_doMixChannel(buf, 1);
                self.Mix_doMixChannel(buf, 2);
                buf += 1

var
    prevL = 0'i8
    prevR = 0'i8

proc nr_stereo(inp: ptr int8, len: int, outp: ptr int8) =
    var input = inp
    var output = outp
    for i in 0..<len:
        let sL = input[] shr 1
        input += 1
        output[] = sL + prevL
        output += 1
        prevL = sL;
        let sR = input[] shr 1
        input += 1
        output[] = sR + prevR
        output += 1
        prevR = sR;

proc playSoundfx(num: int) =
    var p: Player
    p.loadSfxModule(num)
    p.start()
    var fp = open("out.raw", fmWrite)
    while p.playingMusic:
        const kBufSize = 2048
        const kBufSize2 = 2048 * 2
        var inbuf: array[kBufSize2, int8]
        p.Mix_doMix(addr inbuf[0], kBufSize)
        var nrbuf: array[kBufSize2, int8]
        nr_stereo(addr inbuf[0], kBufSize, addr nrbuf[0])
        discard fp.writeBuffer(addr nrbuf[0], kBufSize2)
    close(fp)
    p.stop()

when isMainModule:
    when declared(commandLineParams):
        var s =  commandLineParams()[0]
        var num: int
        discard parseInt(s, num)
        playSoundfx(num)
    else:
        quit("require arguments")
