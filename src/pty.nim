from os import nil
from posix import nil

# The following four POSIX functions are needed to allocate a PTY as a
# master/slave FD pair.
proc posixOpenpt(flags: cint): cint
    {.importc: "posix_openpt", header: """#include <stdlib.h>
                                          #include <fcntl.h>""".}

proc grantpt(fd: cint): cint
    {.importc: "grantpt", header: "<stdlib.h>".}

proc unlockpt(fd: cint): cint
    {.importc: "unlockpt", header: "<stdlib.h>".}

proc ptsname(fd: cint): cstring
    {.importc: "ptsname", header: "<stdlib.h>".}

var TIOCSCTTY {.importc: "TIOCSCTTY", header: "<termios.h>".}: uint

proc failWithLastOsError(context: string) =
  echo "An error occurred. Context: ", context
  os.raiseOsError(os.osLastError())

type
  Pty* = object
    masterFd*: cint
    slaveFd: cint

# The PID of the child process that we fork. This needs to be a global because
# we cannot register a closure as POSIX signal handler in Nim.
var childPid: cint

proc openPty(): Pty =
  var masterFd = posixOpenpt(posix.O_RDWR or posix.O_NOCTTY)
  if masterFd == -1:
    failWithLastOsError("posix_openpt")
  if grantpt(masterFd) == -1:
    failWithLastOsError("grantpt")
  if unlockpt(masterFd) == -1:
    failWithLastOsError("unlockpt")
  let slave = ptsname(masterFd)
  let slaveFd = posix.open(slave, posix.O_RDWR or posix.O_NOCTTY)
  if slaveFd == -1:
    failWithLastOsError("open slave fd")
  return Pty(masterFd: masterFd, slaveFd: slaveFd)

proc redirectStandardStream(fd: cint, standardStream: cint) =
  if posix.dup2(fd, standardStream) == -1:
    failWithLastOsError("dup2 with " & $standardStream)

proc makeControllingTerminal(pty: Pty) =
  if posix.ioctl(pty.slaveFd, TIOCSCTTY) == -1:
    failWithLastOsError("ioctl(.., TIOCSCTTY)")

# Start a shell within the slave device
# TODO Handle failure
proc startShell(pty: Pty, shell: cstring) =
  # We don't need the master FD here
  discard posix.close(pty.masterFd)
  # TODO Might need the PID later
  discard posix.setsid()
  redirectStandardStream(pty.slaveFd, posix.STDIN_FILENO)
  redirectStandardStream(pty.slaveFd, posix.STDOUT_FILENO)
  redirectStandardStream(pty.slaveFd, posix.STDERR_FILENO)
  makeControllingTerminal(pty)

  # The slave FD is no longer needed now either
  discard posix.close(pty.slaveFd)
  # TODO Still have to figure out if this is really necessary
  # TODO If necessary, then use sigaction(2) instead, as explained
  # in signal(2).
  posix.signal(posix.SIGCHLD, posix.SIG_DFL)
  posix.signal(posix.SIGHUP, posix.SIG_DFL)
  posix.signal(posix.SIGINT, posix.SIG_DFL)
  posix.signal(posix.SIGQUIT, posix.SIG_DFL)
  posix.signal(posix.SIGTERM, posix.SIG_DFL)
  posix.signal(posix.SIGALRM, posix.SIG_DFL)
  var args = allocCStringArray(@[$shell])
  defer: deallocCStringArray(args)
  if posix.execvp(shell, args) == -1:
    failWithLastOsError("execvp")

proc setNonBlocking(masterFd: cint) =
  let fl = posix.fcntl(masterFd, posix.F_GETFL, 0)
  if fl == -1:
    failWithLastOsError("fcntl(.., F_GETFL)")
  let mode = fl or posix.O_NONBLOCK
  if posix.fcntl(masterFd, posix.F_SETFL, mode) == -1:
    failWithLastOsError("fcntl(.., F_SETFL)")

proc handleSigchld(sigNum: cint) {.noconv.} =
  var stat: cint
  let p: posix.Pid = posix.waitpid(childPid, stat, posix.WNOHANG)
  if p < 0:
    echo "Waiting for PID failed: ", posix.errno
    quit(posix.errno)
  if childPid != p:
    return
  if posix.WIFEXITED(stat) and posix.WEXITSTATUS(stat) > 0:
    echo "Child exited with status ", posix.WEXITSTATUS(stat)
    quit(1)
  elif posix.WIFSIGNALED(stat):
    echo "Child received signal ", posix.WTERMSIG(stat)
    quit(0)

# TODO Handle failure case by returning a fitting error type,
# or even use Nim's effect system perhaps?
proc spawn*(): Pty =
  let pty = openPty()
  let p = posix.fork()
  if p == -1:
    failWithLastOsError("fork")
  elif p == 0:
    startShell(pty, "dash")
  else:
    childPid = p
    setNonBlocking(pty.masterFd)
    discard posix.close(pty.slaveFd)
    posix.signal(posix.SIGCHLD, handleSigchld)
    return pty
