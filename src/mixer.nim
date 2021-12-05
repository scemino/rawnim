import std/[strformat, logging]
import util
import sdl2
import sdl2/audio
import sdl2/mixer
import scriptptr
import ptrmath
import frac
import sfxplayer

const
    kMixFreq = 44100
    kMixBufSize = 4096
    kMixChannels = 4
    
type
    Mixer* = ref MixerObj
    MixerObj* = object
        sfx*: SfxPlayer
        cvt: AudioCVT
        sounds: array[kMixChannels, ptr Chunk]
        samples: array[kMixChannels, ptr byte]
        
var audioBuffer: array[8192, int8]

proc convertMono8(cvt: var AudioCVT, data: ptr byte, freq, size: int, cvtLen: var int) : ptr byte =
    let kHz = 11025
    assert(kHz / freq <= 4)
    var output = cast[ptr byte](alloc(size * 4 * cvt.len_mult))
    # point resampling
    var pos: Frac
    pos.offset = 0
    pos.inc = cast[uint32]((freq shl BITS) div kHz)
    var len = 0
    while pos.getInt().int < size:
        output[len] = data[pos.getInt().int]
        inc len
        pos.offset += pos.inc
    # convert to mixer format
    cvt.len = len.cint
    cvt.buf = output
    if convertAudio(addr cvt) < 0:
        dealloc(output)
        return nil
    output = cvt.buf
    cvtLen = cvt.len_cvt
    result = output

proc init*(self: var Mixer) =
    discard mixer.init(MIX_INIT_FLUIDSYNTH.cint)
    if openAudio(kMixFreq, AUDIO_S16.uint16, 2, kMixBufSize.cint) < 0:
        warn(&"openAudio failed: {getError()}")
    discard allocateChannels(kMixChannels.cint)
    zeroMem(addr self.cvt, sizeof(self.cvt))
    if buildAudioCVT(self.cvt.addr, AUDIO_S8, 1, 11025, AUDIO_S16.uint16, 2, kMixFreq) < 0:
        warn(&"buildAudioCVT failed: {getError()}")

proc stopSfxMusicCore() =
    hookMusic(nil, nil)

proc stopSfxMusic*(self: Mixer) =
    debug(DBG_SND, "Mixer::stopSfxMusic()")
    self.sfx.stop()
    stopSfxMusicCore()

proc mixSfxPlayer(data: pointer, rawStream: ptr uint8, len: cint) {.cdecl.} =
    setupForeignThreadGc()
    let 
        stream = cast[ptr UncheckedArray[int16]](rawStream)
        count = len div 2 # bytes -> samples
        mixer = cast[ptr Mixer](data)
    zeroMem(addr audioBuffer[0], count)
    mixer.sfx.readSamples(audioBuffer[0].addr, count div 2)
    for i in 0..<count:
        stream[i] = 256 * cast[int16](audioBuffer[i])

proc playSfxMusic*(self: var Mixer, num: int) =
    debug(DBG_SND, &"Mixer::playSfxMusic({num})")
    self.stopSfxMusic()
    self.sfx.play(kMixFreq)
    hookMusic(mixSfxPlayer, addr self)

proc freeSound(self: Mixer, channel: int) =
    freeChunk(self.sounds[channel])
    self.sounds[channel] = nil
    if self.samples[channel] != nil:
        dealloc(self.samples[channel])
        self.samples[channel] = nil

proc update*(self: Mixer) =
    for i in 0..<kMixChannels:
        if self.sounds[i] != nil and playing(i.cint) == 0:
            self.freeSound(i)

proc stopSound*(self: var Mixer, channel: int) =
    discard haltChannel(channel.cint)
    self.freeSound(channel.int)

proc stopAll*(self: var Mixer) =
    for i in 0..<4:
        self.stopSound(i)
    stopSfxMusicCore()

proc setChannelVolume(channel, vol: int) =
    discard volume(channel.cint, (vol * MIX_MAX_VOLUME div 63).cint)

proc playSound(self: var Mixer, channel: int, volume: int, chunk: ptr Chunk, loops: int = 0) =
    self.stopSound(channel)
    if chunk != nil:
        discard playChannel(channel.cint, chunk, loops.cint)
    setChannelVolume(channel, volume)
    self.sounds[channel] = chunk

proc playSoundRaw*(self: var Mixer, channel: int, data: ptr byte, freq: uint16, volume: int) =
    debug(DBG_SND, &"Mixer::playChannel({channel}, {freq}, {volume})")
    var len = READ_BE_UINT16(data) * 2
    let loopLen = READ_BE_UINT16(data + 2) * 2
    if loopLen != 0:
        len = loopLen
    var sampleLen = 0
    var sample = convertMono8(self.cvt, data + 8, freq.int, len.int, sampleLen)
    if sample == nil:
        warn(&"convertMono8 failed: {getError()}")
    var chunk = quickLoad_RAW(sample, sampleLen.uint32)
    self.playSound(channel, volume.int, chunk, if loopLen != 0: -1 else: 0)
    self.samples[channel] = sample
