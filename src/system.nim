import sdl2

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
    PlayerInput* = object
        quit*: bool

proc init*(self: System, title: string) =
    init(INIT_VIDEO or INIT_AUDIO or INIT_JOYSTICK or INIT_GAMECONTROLLER)
    showCursor(false)
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
            quit("bye")
        of WindowEvent:
            var windowEvent = cast[WindowEventPtr](addr(ev))
            if windowEvent.event == WindowEvent_Resized:
                self.w = ev.window.data1
                self.h = ev.window.data2
            elif windowEvent.event == WindowEvent_Close:
                self.pi.quit = true
        else:
            discard
