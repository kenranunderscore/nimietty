# Package

version       = "0.1.0"
author        = "Johannes Maier"
description   = "A tiny terminal emulator"
license       = "MIT"
srcDir        = "src"
bin           = @["nimietty"]

# Dependencies

requires "nim >= 1.4.2"
requires "glfw"
requires "opengl"
requires "glm"
requires "freetype"
