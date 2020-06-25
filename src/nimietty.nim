import sdl2
from pty import nil
from os import sleep

when isMainModule:
  let tty = pty.spawn()
  sleep(2000)
  echo "gogogo"
  var file: File
  if open(file, tty.masterFd, fmReadWriteExisting):
    echo "true"
    var buf: array[100, uint8]
    var actualLen = readBytes(file, buf, 0, 100)
    echo "actualLen = ", actualLen
  else:
    echo "booooo"
  # TODO React to errors
  discard sdl2.init(sdl2.INIT_EVERYTHING)
  let windowFlags = sdl2.SDL_WINDOW_SHOWN or sdl2.SDL_WINDOW_OPENGL
  let window = sdl2.createWindow("Foo", 100, 100, 640, 480, windowFlags)
  let rendererFlags = sdl2.Renderer_Accelerated or sdl2.Renderer_PresentVsync or sdl2.Renderer_TargetTexture
  let renderer = sdl2.createRenderer(window, -1, rendererFlags)
  var evt = sdl2.defaultEvent
  var running = true
  while running:
    while sdl2.pollEvent(evt):
      if evt.kind == sdl2.QuitEvent:
        running = false
        break
      renderer.setDrawColor 0,0,50,255
      renderer.clear()
      renderer.present()
  destroy renderer
  destroy window
  close(file)
