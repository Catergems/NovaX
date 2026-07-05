# modules/fs.nim
# Filesystem module for nvx

import ../eval_types, os, tables

proc callFs*(meth: string, args: seq[Value]): Value =
  case meth
  of "open":
    let path = if args.len > 0: valueToStr(args[0]) else: ""
    var fields = initTable[string, Value]()
    fields["__path"] = Value(kind: vkStr, strVal: path)
    return Value(kind: vkStruct, structType: "__file", fields: fields)
  of "mkdir":
    let name = if args.len > 0: valueToStr(args[0]) else: ""
    if not dirExists(name): createDir(name)
    return Value(kind: vkVoid)
  of "wd":
    return Value(kind: vkStr, strVal: getCurrentDir())
  of "exists":
    let path = if args.len > 0: valueToStr(args[0]) else: ""
    return Value(kind: vkBool, boolVal: fileExists(path) or dirExists(path))
  of "remove":
    let path = if args.len > 0: valueToStr(args[0]) else: ""
    if fileExists(path): removeFile(path)
    elif dirExists(path): removeDir(path)
    return Value(kind: vkVoid)
  else:
    raise newException(ValueError, "fs has no method: " & meth)

proc callFileHandle*(meth: string, path: string, args: seq[Value]): Value =
  case meth
  of "append":
    let f = open(path, fmAppend)
    f.write(if args.len > 0: valueToStr(args[0]) else: "")
    f.close()
    return Value(kind: vkVoid)
  of "write":
    writeFile(path, if args.len > 0: valueToStr(args[0]) else: "")
    return Value(kind: vkVoid)
  of "read":
    return Value(kind: vkStr, strVal: readFile(path))
  of "close":
    return Value(kind: vkVoid) # no-op, files are opened/closed per op
  else:
    raise newException(ValueError, "file handle has no method: " & meth)
