import sdl2
from pty import nil
from posix import nil

type
  CursorPosition = object
    x, y: uint8
  TerminalState = object
    grid: array[10, array[80, char]]
    pos: CursorPosition
  ReaderFds = object
    pty: cint
    commPipe: cint

var
  state = TerminalState(pos: CursorPosition(x: 0, y: 0))

proc readPtyAndUpdateState(fds: ReaderFds) =
  var wrapped = false
  let nFd: cint = max(fds.pty, fds.commPipe) + 1
  var readable: posix.TFdSet
  # TODO stop using Timeval of 0 to make select block again, as it should
  var tv: posix.Timeval
  # TODO how to find a good value here? `BUFSIZ` maybe?
  const bufferSize = 512
  while true:
    posix.FD_ZERO(readable)
    posix.FD_SET(fds.commPipe, readable)
    posix.FD_SET(fds.pty, readable)
    if posix.select(nFd, addr(readable), nil, nil, nil) <= 0:
      echo "select() failed; quitting"
      quit(1)
    echo "selected"
    if posix.FD_ISSET(fds.commPipe, readable) > 0:
      echo "read from pipe"
      # TODO actually read something? or use something else, maybe semaphore?
      break
    if posix.FD_ISSET(fds.pty, readable) > 0:
      var buf: array[bufferSize, uint8]
      let bytesRead = posix.read(fds.pty, addr(buf), bufferSize)
      if bytesRead == 0:
        echo "Nothing to read, quitting"
        quit(0)
      elif bytesRead == -1:
        echo "Failed to read from PTY"
        quit(1)
      for b in buf[0 .. bytesRead-1]:
        let c = chr(b)
        if c == '\r':
          state.pos.x = 0
        else:
          if c != '\n':
            state.grid[state.pos.y][state.pos.x] = c
            inc(state.pos.x)
            if state.pos.x >= 80:
              state.pos.x = 0
              inc(state.pos.y)
              wrapped = true
            else:
              wrapped = false
          elif not wrapped:
            inc(state.pos.y)
            wrapped = false
    else:
      echo "not set"

when isMainModule:
  let tty = pty.spawn()
  var file: File
  if open(file, tty.masterFd, fmReadWriteExisting):
    # TODO React to errors
    discard sdl2.init(sdl2.INIT_EVERYTHING)
    echo "SDL initialized successfully"
    let windowFlags = sdl2.SDL_WINDOW_SHOWN or sdl2.SDL_WINDOW_OPENGL
    let window = sdl2.createWindow("Foo", 100, 100, 640, 480, windowFlags)
    let rendererFlags = sdl2.Renderer_Accelerated or sdl2.Renderer_PresentVsync or sdl2.Renderer_TargetTexture
    let renderer = sdl2.createRenderer(window, -1, rendererFlags)
    var evt = sdl2.defaultEvent
    var running = true
    var counter = 0
    # Run PTY reader and state update in a background thread.
    # We open a UNIX pipe to communicate the end of the main program
    # with the background/reader thread.
    var pipeFds: array[2, cint]
    if posix.pipe(pipeFds) < 0:
      # TODO errno
      echo "couldn't open pipe"
      quit(1)
    defer:
      discard posix.close(pipeFds[0])
      discard posix.close(pipeFds[1])
    var reader: Thread[ReaderFds]
    createThread(reader, readPtyAndUpdateState, ReaderFds(pty: tty.masterFd, commPipe: pipeFds[0]))
    defer: joinThread(reader)

    while running:
      counter += 1
      while sdl2.pollEvent(evt):
        if evt.kind == sdl2.QuitEvent:
          echo "quitting..."
          running = false
          break

      # Write some dummy stuff to the PTY
      if counter == 200:
        echo "writing..."
        file.write("l")
        file.write("s")
        file.write("\n")

      # Draw the terminal window
      renderer.setDrawColor 0,0,50,255
      renderer.clear()
      renderer.present()

    # FIXME
    var foo = "foo"
    discard posix.write(pipeFds[1], addr(foo), 4)
    echo "final state: ", state.grid[0..2]
    destroy renderer
    destroy window
    close(file)
  else:
    echo "could not open master fd as file"
