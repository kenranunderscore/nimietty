from pty import nil

when isMainModule:
  let tty = pty.spawn()
  echo("Hello, World!")
