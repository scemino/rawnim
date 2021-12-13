import std/strformat
import ptrmath
import os
import resource
import datatype

const 
    MAX_OPCODES = 27
    MAX_FILESIZE = 0x10000
    MAX_TASKS = 64

type
    AddressMode = enum
        ADDR_FUNC, ADDR_LABEL, ADDR_TASK
    Opcode = enum
        op_movConst,
        op_mov,
        op_add,
        op_addConst,
        # 0x04
        op_call,
        op_ret,
        op_yieldTask,
        op_jmp,
        # 0x08
        op_installTask,
        op_jmpIfVar,
        op_condJmp,
        op_setPalette,
        # 0x0C
        op_changeTasksState,
        op_selectPage,
        op_fillPage,
        op_copyPage,
        # 0x10
        op_updateDisplay,
        op_removeTask,
        op_drawString,
        op_sub,
        # 0x14
        op_and,
        op_or,
        op_shl,
        op_shr,
        # 0x18
        op_playSound,
        op_updateResources,
        op_playMusic

var 
    gAddresses: array[MAX_FILESIZE, set[AddressMode]]
    gHistogramOp: array[MAX_OPCODES, int]

proc readAllBytes(filename: string) : seq[byte] =
    var fp = open(filename)
    result = newSeq[byte](getFileSize(fp))
    discard fp.readBuffer(addr result[0], result.len)
    close(fp)

proc readWord(p: ptr byte) : uint16 =
    (p[0].uint16 shl 8) or p[1] # BE

proc checkOpcode(address: uint16, opcode: byte, args: array[4, int]) =
    if opcode < MAX_OPCODES:
        case opcode.Opcode
        of op_call:
            let offset = args[0]
            gAddresses[offset].incl ADDR_FUNC
        of op_jmp:
            let offset = args[0]
            if offset==0:
                quit(&"address={address:02X} op_jmp")
            gAddresses[offset].incl ADDR_LABEL
        of op_installTask:
            let offset = args[1]
            gAddresses[offset].incl ADDR_TASK
        of op_condJmp:
            let offset = args[3]
            if offset==0:
                quit(&"address={address:02X} op_condJmp")
            gAddresses[offset].incl ADDR_LABEL
        of op_jmpIfVar:
            let offset = args[1]
            if offset==0:
                quit(&"address={address:02X} op_jmpIfVar")
            gAddresses[offset].incl ADDR_LABEL
        else:
            discard
        inc gHistogramOp[opcode.int]

proc printOpcode(address: uint16, opcode: byte, args: array[4, int]) =
    if gAddresses[address].contains ADDR_FUNC:
        echo &"\n{address:04X}: // func_{address:04X}"
    if gAddresses[address].contains ADDR_TASK:
        echo &"\n{address:04X}: // START OF SCRIPT TASK"
    if gAddresses[address].contains ADDR_LABEL:
        echo &"{address:04X}: loc_{address:04X}:"
    stdout.write &"{address:04X}: ({opcode:02X}) "
    if opcode > op_playMusic.byte and (opcode and 0xC0) == 0:
        echo ""
        return
    if opcode < MAX_OPCODES:
        case opcode.OpCode:
        of op_movConst:
            echo &"VAR(0x{args[0]:02X}) = {args[1]}"
        of op_mov:
            echo &"VAR(0x{args[0]:02X}) = VAR(0x{args[1]:02X})"
        of op_addConst:
            if args[1] < 0:
                echo &"VAR(0x{args[0]:02X}) -= {-args[1]}"
            else:
                echo &"VAR(0x{args[0]:02X}) += {args[1]}"
        of op_add:
            echo &"VAR(0x{args[0]:02X}) += VAR(0x{args[1]:02X})"
        of op_call:
            echo &"call(@{args[0]:04X})"
        of op_ret:
            echo "ret // RETURN FROM CALL";
        of op_yieldTask:
            echo "yieldTask // PAUSE SCRIPT TASK";
        of op_jmp:
            echo &"jmp(@{args[0]:04X})"
        of op_installTask:
            echo &"installTask({args[0]}, @{args[1]:04X})"
        of op_jmpIfVar:
            echo &"jmpIfVar(VAR(0x{args[0]:02X}), @{args[1]:04X})"
        of op_condJmp:
            stdout.write &"jmpIf(VAR(0x{args[1]:02X})"
            case args[0] and 7:
            of 0:
                stdout.write " == "
            of 1:
                stdout.write " != "
            of 2:
                stdout.write " > "
            of 3:
                stdout.write " >= "
            of 4:
                stdout.write " < "
            of 5:
                stdout.write " <= "
            else:
                stdout.write " ?? "
            if (args[0] and 0x80) != 0: 
                stdout.write &"VAR(0x{args[2]:02X}),"
            elif (args[0] and 0x40) != 0:
                stdout.write &"{cast[int16](args[2])},"
            else:
                stdout.write &"{args[2]},"
            echo &" @{args[3]:04X})"
        of op_setPalette:
            echo &"setPalette(num={args[0]})"
        of op_changeTasksState:
            assert(args[0] < MAX_TASKS and args[1] < MAX_TASKS)
            assert(args[0] <= args[1])
            echo &"changeTasksState(start={args[0]},end={args[1]},state={args[2]})"
        of op_selectPage:
            echo &"selectPage(page={args[0]})"
        of op_fillPage:
            echo &"fillPage(page={args[0]}, color={args[1]})"
        of op_copyPage:
            echo &"copyPage(src={args[0]}, dst={args[1]})"
        of op_updateDisplay:
            echo &"updateDisplay(page={args[0]})"
        of op_removeTask:
            echo &"removeTask // STOP SCRIPT TASK"
        of op_drawString:
            echo &"drawString(str=0x{args[0]:03X}, x={args[1]}, y={args[2]}, color={args[3]})"
        of op_sub:
            echo &"VAR(0x{args[0]:02X}) -= VAR(0x{args[1]:02X})"
        of op_and:
            echo &"VAR(0x{args[0]:02X}) &= {args[1]}"
        of op_or:
            echo &"VAR(0x{args[0]:02X}) |= {args[1]}"
        of op_shl:
            echo &"VAR(0x{args[0]:02X}) <<= {args[1]}"
        of op_shr:
            echo &"VAR(0x{args[0]:02X}) >>= {args[1]}"
        of op_playSound:
            echo &"playSound(res={args[0]}, freq={args[1]}, vol={args[2]}, channel={args[3]})"
        of op_updateResources:
            echo &"updateResources(res={args[0]})"
        of op_playMusic:
            echo &"playMusic(res={args[0]}, delay={args[1]}, pos={args[2]})"
    else:
        if (opcode and 0xC0) != 0:
            let offset = args[0].uint16
            stdout.write &"drawShape(code=0x{opcode:02X}, x={args[1]}, y={args[2]}"
            echo &"); // offset=0x{offset shl 1:04X} (bank{args[3]}.mat)"

proc parse(buf: ptr byte, size: int, visitOpcode: proc(a: uint16, op: byte, args: array[4,int])) =
    var p = buf
    while p < buf + size:
        let address = (cast[int](p) - cast[int](buf)).uint16
        var a, b, c, d: int
        let op = p[]
        p += 1
        if (op and 0x80) != 0:
            a = p[].int; p += 1 # offset_lo
            b = p[].int; p += 1 # x
            c = p[].int; p += 1 # y
            var args = [(((op.int and 0x7F) shl 8) or a), b, c, 1]
            visitOpcode(address, op, args)
        elif (op and 0x40) != 0:
            a = readWord(p).int; p += 2 # offset
            b = p[].int; p += 1
            if (op and 0x20) == 0 and (op and 0x10) == 0:
                p += 1
            c = p[].int; p += 1
            if (op and 8) == 0 and (op and 4) == 0:
                p += 1
            if ((op and 2) == 0 and (op and 1) != 0) or ((op and 2) != 0 and (op and 1)==0):
                p += 1
            var args = [ a, b, c, if ((op and 3) == 3): 2 else: 1 ]
            visitOpcode(address, op, args)
        else:
            case op:
            of 0: # op_movConst
                a = p[].int; p += 1
                b = cast[int16](readWord(p)); p += 2
            of 1: # op_mov
                a = p[].int; p += 1
                b = p[].int; p += 1
            of 2: # op_add
                a = p[].int; p += 1
                b = p[].int; p += 1
            of 3: # op_addConst
                a = p[].int; p += 1
                b = cast[int16](readWord(p)); p += 2
            of 4: # op_call
                a = readWord(p).int; p += 2
            of 5: # op_ret
                discard
            of 6: # op_yieldTask
                discard
            of 7: # op_jmp
                a = readWord(p).int; p += 2
            of 8: # op_installTask
                a = p[].int; p += 1
                b = readWord(p).int; p += 2
            of 9: # op_jmpIfVar
                a = p[].int; p += 1
                b = readWord(p).int; p += 2
            of 10: # op_condJmp
                a = p[].int; p += 1
                b = p[].int; p += 1
                if (a and 0x80) != 0:
                    c = p[].int; p += 1
                elif (a and 0x40) != 0:
                    c = cast[int16](readWord(p)); p += 2
                else:
                    c = p[].int; p += 1
                d = readWord(p).int; p += 2;
            of 11: # op_setPalette
                a = p[].int; p += 1
                p += 1
            of 12: # op_changeTasksState
                a = p[].int; p += 1
                b = p[].int; p += 1
                c = p[].int; p += 1
            of 13: # op_selectPage
                a = p[].int; p += 1
            of 14: # op_fillPage
                a = p[].int; p += 1
                b = p[].int; p += 1
            of 15: # op_copyPage
                a = p[].int; p += 1
                b = p[].int; p += 1
            of 16: # op_updateDisplay
                a = p[].int; p += 1
            of 17: # op_removeTask
                discard
            of 18: # op_drawString
                a = readWord(p).int; p += 2;
                b = p[].int; p += 1
                c = p[].int; p += 1
                d = p[].int; p += 1
            of 19: # op_sub
                a = p[].int; p += 1
                b = p[].int; p += 1
            of 20: # op_and
                a = p[].int; p += 1
                b = readWord(p).int; p += 2;
            of 21: # op_or
                a = p[].int; p += 1
                b = readWord(p).int; p += 2;
            of 22: # op_shl
                a = p[].int; p += 1
                b = readWord(p).int; p += 2;
            of 23: # op_shr
                a = p[].int; p += 1
                b = readWord(p).int; p += 2
            of 24: # op_playSound
                a = readWord(p).int; p += 2
                b = p[].int; p += 1
                c = p[].int; p += 1
                d = p[].int; p += 1
            of 25: # op_updateResources
                a = readWord(p).int; p += 2
            of 26: # op_playMusic
                a = readWord(p).int; p += 2;
                b = readWord(p).int; p += 2;
                c = p[].int; p += 1
            else:
                quit(&"invalid opcode: {op}")
            let args = [a, b, c, d]
            visitOpcode(address, op, args)

iterator resources(self: Resource): MemEntry =
    for i in 0..<self.numMemList:
        if self.memList[i].entryType == RT_BYTECODE:
            yield self.memList[i]

when isMainModule:
    when declared(commandLineParams):
        let params = commandLineParams()
        if params.len > 0:
            let path = params[0]
            if dirExists(path):
                echo &"directory: {path}"
                var res = newResource(path)
                res.readEntries()
                for entry in res.resources():
                    var p = newSeq[byte](entry.unpackedSize)
                    if res.readBank(entry, addr p[0]):
                        parse(addr p[0], p.len, checkOpcode)
                        parse(addr p[0], p.len, printOpcode)
            else:
                var buffer = readAllBytes(path)
                parse(addr buffer[0], buffer.len, checkOpcode)
                parse(addr buffer[0], buffer.len, printOpcode)
    else:
        quit("You need to provide a path")

