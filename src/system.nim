import sdl2
import sdl2/joystick
import sdl2/gamecontroller

const 
    joystickIndex = 0
    joystickCommitValue = 16384

type 
    System* = ref SystemObj
    SystemObj* = object
        pi*: PlayerInput
        window: WindowPtr
        renderer: RendererPtr
        texture: TexturePtr
        aspectRatio: array[4, float]
        w, h: cint
        texW, texH: int
        joystick: JoystickPtr
        controller: GameControllerPtr
    PlayerDirection* = enum
        DIR_LEFT  = 1 shl 0
        DIR_RIGHT = 1 shl 1
        DIR_UP    = 1 shl 2
        DIR_DOWN  = 1 shl 3
    PlayerInput* = object
        dirMask*: set[PlayerDirection]
        quit*: bool
        action*: bool # run,shoot
        code*: bool
        pause*: bool
        lastChar*: char

proc init*(self: System, title: string) =
    init(INIT_VIDEO or INIT_AUDIO or INIT_JOYSTICK or INIT_GAMECONTROLLER)
    #showCursor(false)
    # SetHint(HINT_RENDER_SCALE_QUALITY, "1")

    var windowW = 640.cint
    var windowH = 480.cint
    var flags = SDL_WINDOW_RESIZABLE.uint32
    self.window = createWindow(title, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, windowW, windowH, flags)
    self.window.getSize(self.w, self.h)

    self.renderer = createRenderer(self.window, -1, Renderer_Accelerated.cint)
    self.renderer.setDrawColor(0, 0, 0, 255)
    self.renderer.clear()
    self.aspectRatio[0] = 0
    self.aspectRatio[1] = 0
    self.aspectRatio[2] = 1
    self.aspectRatio[3] = 1
    if numJoysticks() > 0:
        discard gameControllerAddMapping("gamecontrollerdb.txt")
        if isGameController(joystickIndex.cint):
            self.controller = gameControllerOpen(joystickIndex)
        if self.controller == nil:
            self.joystick = joystickOpen(joystickIndex)

proc updateScreen*(self: System) =
    self.renderer.present()

func getTimeStamp*(self: System): uint32 =
    getTicks()

func sleep*(self: System, duration: uint32) =
    delay(duration)

proc prepareScreen*(self: System, w, h: var int, ar: var array[4, float]) =
    w = self.w
    h = self.h
    ar[0] = self.aspectRatio[0]
    ar[1] = self.aspectRatio[1]
    ar[2] = self.aspectRatio[2]
    ar[3] = self.aspectRatio[3]
    if self.renderer != nil:
        self.renderer.clear()

proc setScreenPixels555*(self: System, data: ptr uint16, w, h: int) =
    if self.texture == nil:
        self.texture = self.renderer.createTexture(SDL_PIXELFORMAT_RGB555.uint32, SDL_TEXTUREACCESS_STREAMING.cint, w.cint, h.cint)
        self.texW = w
        self.texH = h
    assert(w <= self.texW and h <= self.texH)
    var r: Rect
    r.w = w.cint
    r.h = h.cint
    if w != self.texW and h != self.texH:
        r.x = (self.texW - w).cint div 2
        r.y = (self.texH - h).cint div 2
    else:
        r.x = 0
        r.y = 0
    self.texture.updateTexture(addr r, data, (w * sizeof(uint16)).cint)
    self.renderer.copy(self.texture, nil, nil)

proc processEvents*(self: System) =
    var ev: Event
    while pollEvent(ev):
        case ev.kind:
        of QuitEvent:
            self.pi.quit = true
        of WindowEvent:
            var windowEvent = cast[WindowEventPtr](addr(ev))
            if windowEvent.event == WindowEvent_Resized:
                self.w = ev.window.data1
                self.h = ev.window.data2
            elif windowEvent.event == WindowEvent_Close:
                self.pi.quit = true
        of KeyDown:
            var keyEvent = cast[KeyboardEventPtr](addr(ev))
            self.pi.lastChar = cast[char](keyEvent.keysym.sym)
            case keyEvent.keysym.sym:
            of K_LEFT:
                self.pi.dirMask.incl DIR_LEFT
            of K_RIGHT:
                self.pi.dirMask.incl DIR_RIGHT
            of K_UP:
                self.pi.dirMask.incl DIR_UP
            of K_DOWN:
                self.pi.dirMask.incl DIR_DOWN
            of K_SPACE, K_RETURN:
                self.pi.action = true
            else:
                discard
        of KeyUp:
            var keyEvent = cast[KeyboardEventPtr](addr(ev))
            case keyEvent.keysym.sym:
            of K_LEFT:
                self.pi.dirMask.excl DIR_LEFT
            of K_RIGHT:
                self.pi.dirMask.excl DIR_RIGHT
            of K_UP:
                self.pi.dirMask.excl DIR_UP
            of K_DOWN:
                self.pi.dirMask.excl DIR_DOWN
            of K_SPACE, K_RETURN:
                self.pi.action = false
            of K_ESCAPE:
                self.pi.quit = true
            of K_c:
                self.pi.code = true
            of K_p:
                self.pi.pause = true
            else:
                discard
        of ControllerDeviceAdded:
            var controllerEvent = cast[ControllerDeviceEventPtr](addr(ev))
            self.controller = gameControllerOpen(controllerEvent.which.cint)
        of ControllerDeviceRemoved:
            close(self.controller)
        of JoyHatMotion:
            if self.joystick != nil:
                self.pi.dirMask.reset()
                if (ev.jhat.value and SDL_HAT_UP.byte) != 0:
                    self.pi.dirMask.incl DIR_UP
                if (ev.jhat.value and SDL_HAT_DOWN.byte) != 0:
                    self.pi.dirMask.incl DIR_DOWN
                if (ev.jhat.value and SDL_HAT_LEFT.byte) != 0:
                    self.pi.dirMask.incl DIR_LEFT
                if (ev.jhat.value and SDL_HAT_RIGHT.byte) != 0:
                    self.pi.dirMask.incl DIR_RIGHT
        of JoyAxisMotion:
            if self.joystick != nil:
                case ev.jaxis.axis:
                of 0:
                    self.pi.dirMask.excl {DIR_RIGHT, DIR_LEFT}
                    if ev.jaxis.value > joystickCommitValue:
                        self.pi.dirMask.incl DIR_RIGHT
                    elif ev.jaxis.value < -joystickCommitValue:
                        self.pi.dirMask.incl DIR_LEFT
                of 1:
                    self.pi.dirMask.excl {DIR_UP, DIR_DOWN}
                    if ev.jaxis.value > joystickCommitValue:
                        self.pi.dirMask.incl DIR_DOWN
                    elif ev.jaxis.value < -joystickCommitValue:
                        self.pi.dirMask.incl DIR_UP
                else:
                    discard
        of JoyButtonDown, JoyButtonUp:
            if self.joystick != nil:
                self.pi.action = ev.jbutton.state == 1
        of ControllerAxisMotion:
            if self.controller != nil:
                case ev.caxis.axis:
                of SDL_CONTROLLER_AXIS_LEFTX, SDL_CONTROLLER_AXIS_RIGHTX:
                    if ev.caxis.value < -joystickCommitValue:
                        self.pi.dirMask.incl DIR_LEFT
                    else:
                        self.pi.dirMask.excl DIR_LEFT
                    if ev.caxis.value > joystickCommitValue:
                        self.pi.dirMask.incl DIR_RIGHT
                    else:
                        self.pi.dirMask.excl DIR_RIGHT
                of SDL_CONTROLLER_AXIS_LEFTY, SDL_CONTROLLER_AXIS_RIGHTY:
                    if ev.caxis.value < -joystickCommitValue:
                        self.pi.dirMask.incl DIR_UP
                    else:
                        self.pi.dirMask.excl DIR_UP
                    if ev.caxis.value > joystickCommitValue:
                        self.pi.dirMask.incl DIR_DOWN
                    else:
                        self.pi.dirMask.excl DIR_DOWN
                else: discard
        of ControllerButtonDown, ControllerButtonUp:
            if self.controller != nil:
                let pressed = ev.cbutton.state == 1
                case ev.cbutton.button:
                of SDL_CONTROLLER_BUTTON_GUIDE:
                    self.pi.quit = pressed
                of SDL_CONTROLLER_BUTTON_LEFTSHOULDER, SDL_CONTROLLER_BUTTON_RIGHTSHOULDER:
                    self.pi.code = pressed
                of SDL_CONTROLLER_BUTTON_START:
                    self.pi.pause = pressed
                of SDL_CONTROLLER_BUTTON_DPAD_UP:
                    if pressed:
                        self.pi.dirMask.incl DIR_UP
                    else:
                        self.pi.dirMask.excl DIR_UP
                of SDL_CONTROLLER_BUTTON_DPAD_DOWN:
                    if pressed:
                        self.pi.dirMask.incl DIR_DOWN
                    else:
                        self.pi.dirMask.excl DIR_DOWN
                of SDL_CONTROLLER_BUTTON_DPAD_LEFT:
                    if pressed:
                        self.pi.dirMask.incl DIR_LEFT
                    else:
                        self.pi.dirMask.excl DIR_LEFT
                of SDL_CONTROLLER_BUTTON_DPAD_RIGHT:
                    if pressed:
                        self.pi.dirMask.incl DIR_RIGHT
                    else:
                        self.pi.dirMask.excl DIR_RIGHT
                of SDL_CONTROLLER_BUTTON_A:
                    self.pi.action = pressed
                of SDL_CONTROLLER_BUTTON_B:
                    if pressed:
                        self.pi.dirMask.incl DIR_UP
                    else:
                        self.pi.dirMask.excl DIR_UP
                else:
                    discard
        else:
            discard
