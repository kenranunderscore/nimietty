import opengl

# TODO Enum for shader type
proc loadShader(code: string, shaderType: GLenum): GLuint =
  let id = glCreateShader(shaderType)
  echo "hi"
  var source = allocCStringArray(@[code])
  echo "foo loaded"
  defer: deallocCStringArray(source)
  glShaderSource(id, 1, source, nil)
  echo "here"
  glCompileShader(id)
  var success: GLint
  glGetShaderiv(id, GL_COMPILE_STATUS, addr(success))
  if success != 0:
    return id
  else:
    # FIXME
    echo "could not compile shader"
    quit(-1)
  return id

proc loadShaderFromFile*(path: string, shaderType: GLenum): GLuint =
  let code = readFile(path)
  loadShader(code, shaderType)
