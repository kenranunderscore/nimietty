import staticglfw as glfw
import opengl
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
    discard glfw.init()
    defer: glfw.terminate()
    echo "GLFW initialized successfully"
    # glfwWindowHint(GLFWContextVersionMajor, 3)
    # glfwWindowHint(GLFWContextVersionMinor, 3)
    # glfwWindowHint(GLFWOpenglForwardCompat, GLFW_TRUE) # Used for Mac
    # glfwWindowHint(GLFWOpenglProfile, GLFW_OPENGL_CORE_PROFILE)
    # glfwWindowHint(GLFWResizable, GLFW_FALSE)
    let window = glfw.createWindow(800, 600, "foo", nil, nil)
    defer: window.destroyWindow()
    # discard window.setKeyCallback(keyProc)
    window.makeContextCurrent()
    opengl.loadExtensions()

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

    while glfw.windowShouldClose(window) == 0:
      glfw.pollEvents()
      glClearColor(0.68f, 1f, 0.34f, 1f)
      glClear(GL_COLOR_BUFFER_BIT)
      window.swapBuffers()

    # FIXME
    var foo = "foo"
    discard posix.write(pipeFds[1], addr(foo), 4)
    echo "final state: ", state.grid[0..2]
    close(file)
  else:
    echo "could not open master fd as file"
