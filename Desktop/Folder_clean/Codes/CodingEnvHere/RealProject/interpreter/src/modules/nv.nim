# modules/nv.nim
# Standard I/O module for nvx

import ../eval_types, strutils

proc callNv*(meth: string, args: seq[Value], env: Env): Value =
  case meth
  of "echoln", "println":
    echo(if args.len > 0: valueToStr(args[0]) else: "")
    return Value(kind: vkVoid)
  of "echo", "print":
    stdout.write(if args.len > 0: valueToStr(args[0]) else: "")
    stdout.flushFile()
    return Value(kind: vkVoid)
  of "echof":
    let s = if args.len > 0: valueToStr(args[0]) else: ""
    echo interpolate(s, env)
    return Value(kind: vkVoid)
  of "read":
    try: return Value(kind: vkStr, strVal: stdin.readLine())
    except EOFError: return Value(kind: vkStr, strVal: "")
  of "readln":
    try: return Value(kind: vkStr, strVal: stdin.readLine())
    except EOFError: return Value(kind: vkStr, strVal: "")
  else:
    raise newException(ValueError, "nv has no method: " & meth)
