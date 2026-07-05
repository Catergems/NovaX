# modules/task.nim
# Task/concurrency module for nvx

import ../eval_types, os

proc callTask*(meth: string, args: seq[Value], callLine: int): Value =
  case meth
  of "sleep":
    let ms = if args.len > 0 and args[0].kind == vkInt: args[0].intVal * 1000
             elif args.len > 0 and args[0].kind == vkFloat: int(args[0].floatVal * 1000.0)
             else: 0
    sleep(ms)
    return Value(kind: vkVoid)
  of "defer", "run":
    if args.len > 0 and args[0].kind == vkFun:
      return gCallFun(args[0], @[], callLine)
    return Value(kind: vkVoid)
  else:
    raise newException(ValueError, "task has no method: " & meth)
