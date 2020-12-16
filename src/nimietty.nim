import staticglfw as glfw
import opengl
import freetype/freetype
import posix
import glm
import tables

import pty
import shader

type
  CursorPosition = object
    x, y: uint8
  TerminalState = object
    grid: array[10, array[80, char]]
    pos: CursorPosition
  ReaderFds = object
    pty: cint
    commPipe: cint
  Character = object
    textureId: GLuint
    width, height: GLint
    left, top: GLint
    advance: GLfloat

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

proc keyCallback(window: glfw.Window, key: cint, scancode: cint, action: cint, modifiers: cint) {.cdecl.} =
  if key == glfw.KEY_ESCAPE:
    window.setWindowShouldClose(1)

proc renderText(chars: Table[int, Character], vao: GLuint, vbo: GLuint, p: GLuint, text: string, x: GLfloat, y: GLfloat, scale: GLfloat, color: glm.Vec3[GLfloat]) =
  glUseProgram(p)
  glActiveTexture(GL_TEXTURE0)
  glBindVertexArray(vao)
  glUniform3f(glGetUniformLocation(p, "textColor"), color.x, color.y, color.z);

  var x = x
  for c in text:
    let ch = chars[int c]
    let xpos = x + GLfloat(ch.left) * scale
    let ypos = y - GLfloat(ch.height - ch.top) * scale
    let w = GLfloat(ch.width) * scale
    let h = GLfloat(ch.height) * scale
    var vertices: array[6, array[4, GLfloat]] =
      [
            [ xpos,     ypos + h,   0.0, 0.0 ],
            [ xpos,     ypos,       0.0, 1.0 ],
            [ xpos + w, ypos,       1.0, 1.0 ],

            [ xpos,     ypos + h,   0.0, 0.0 ],
            [ xpos + w, ypos,       1.0, 1.0 ],
            [ xpos + w, ypos + h,   1.0, 0.0 ]
      ]
    glBindTexture(GL_TEXTURE_2D, ch.textureId)
    glBindBuffer(GL_ARRAY_BUFFER, vbo)
    glBufferSubData(GL_ARRAY_BUFFER, 0, GLsizeiptr(sizeof(vertices)), vertices.addr);
    glBindBuffer(GL_ARRAY_BUFFER, 0)
    glDrawArrays(GL_TRIANGLES, 0, 6)
    x += ch.advance / 64.0 * scale

  glBindVertexArray(0)
  glBindTexture(GL_TEXTURE_2D, 0)

## Initialize GLFW. Quit on failure as we cannot do anything afterwards.
proc initGlfw() =
  echo "GLFW::Initializing"
  let res = glfw.init()
  if res == 0:
    echo "GLFW::Initialization failed"
    quit(-1)

# Terminate and cleanup the GLFW session.
proc terminateGlfw() =
  echo "GLFW::Terminating"
  glfw.terminate()

proc initGraphics() =
  initGlfw()
  opengl.loadExtensions()
  glfw.windowHint(glfw.ContextVersionMajor, 3)
  glfw.windowHint(glfw.ContextVersionMinor, 3)
  glfw.windowHint(glfw.OpenglProfile, glfw.OpenglCoreProfile)
  glfw.windowHint(glfw.OpenglForwardCompat, glfw.True)
  glfw.windowHint(glfw.Resizable, glfw.False)

proc main() =
  let tty = pty.spawn()
  # TODO React to errors
  initGraphics()
  defer: terminateGlfw()
  let window = glfw.createWindow(800, 600, "foo", nil, nil)
  defer: glfw.destroyWindow(window)
  discard glfw.setKeyCallback(window, keyCallback)
  glfw.makeContextCurrent(window)

  glEnable(GL_CULL_FACE)
  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glViewport(0, 0, GLint(800), 600)
  let vertexShader = shader.loadShaderFromFile("shaders/vs.glsl", GL_VERTEX_SHADER)
  let fragmentShader = shader.loadShaderFromFile("shaders/fs.glsl", GL_FRAGMENT_SHADER)
  let program = glCreateProgram()
  glAttachShader(program, vertexShader)
  glAttachShader(program, fragmentShader)
  glLinkProgram(program)
  glDeleteShader(vertexShader)
  glDeleteShader(fragmentShader)

  var projection = ortho(GLfloat(0.0), 800, 0, 600, -1, 1)
  var loc = glGetUniformLocation(program, "projection")
  glUseProgram(program)
  glUniformMatrix4fv(loc, count = 1, transpose = false, projection.caddr)

  var ftLib: FT_Library
  echo "freetype init result: ", FT_Init_FreeType(ftLib)
  var face: FT_Face
  if FT_New_Face(ftLib, "foo.ttf", 0, face) > 0:
    echo "didn't work"
    quit(-1)
  echo FT_Set_Pixel_Sizes(face, 0, 100)
  glPixelStorei(GL_UNPACK_ALIGNMENT, 1)

  var chars = initTable[int, Character]()
  for i in 0 ..< 128:
    if FT_Load_Char(face, culong(i), FT_LOAD_RENDER) > 0:
      echo "could not be loaded: ", i
      quit(-1)
    var tex: GLuint
    glGenTextures(1, addr(tex))
    glBindTexture(GL_TEXTURE_2D, tex)
    let w = GLint face.glyph.bitmap.width
    let h = GLint face.glyph.bitmap.rows
    glTexImage2D(GL_TEXTURE_2D, GLint(0), GLint(GL_RED), GLsizei(w), GLint(h), GLint(0), GL_RED, GL_UNSIGNED_BYTE, face.glyph.bitmap.buffer)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)
    let cx = Character(textureId: tex, width: w, height: h, left: face.glyph.bitmap_left, top: face.glyph.bitmap_top, advance: GLfloat face.glyph.advance.x)
    echo "loaded ", cx
    chars[i] = cx

  glBindTexture(GL_TEXTURE_2D, 0)

  echo "done face: ", FT_Done_Face(face)
  echo "done freetype: ", FT_Done_FreeType(ftLib)

  var vbo, vao: GLuint
  glGenVertexArrays(1, vao.addr)
  glGenBuffers(1, vbo.addr)
  glBindVertexArray(vao)
  glBindBuffer(GL_ARRAY_BUFFER, vbo)
  glBufferData(GL_ARRAY_BUFFER, size = GLsizeiptr(sizeof(GLfloat) * 6 * 4), nil, GL_DYNAMIC_DRAW)
  glVertexAttribPointer(index = 0, size = 4, type = cGL_FLOAT, normalized = false, stride = 4 * sizeof(GLfloat), pointer = cast[pointer](0))
  glEnableVertexAttribArray(index = 0)
  glBindBuffer(GL_ARRAY_BUFFER, GLuint(0))
  glBindVertexArray(GLuint(0))

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
    glClearColor(0.2, 0.3, 0.3, 1.0)
    glClear(GL_COLOR_BUFFER_BIT)
    renderText(chars, vao, vbo, program, "This is sample text", 25, 25, 0.3, glm.vec3(GLfloat 0.5, 0.8, 0.2))
    renderText(chars, vao, vbo, program, "(C) LearnOpenGL.com", 40, 470, 0.5, glm.vec3(GLfloat 0.3, 0.7, 0.9))
    window.swapBuffers()

  glDeleteVertexArrays(1, addr(vao))
  glDeleteBuffers(1, addr(vbo))

  # FIXME
  var foo = "foo"
  discard posix.write(pipeFds[1], addr(foo), 4)
  echo "final state: ", state.grid[0..2]

when isMainModule:
  main()
