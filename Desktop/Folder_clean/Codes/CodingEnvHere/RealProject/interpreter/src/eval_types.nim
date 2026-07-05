# eval_types.nim
# Shared Value, Env types and helpers used by eval and all modules

import ast, tables, strutils

type
  ValueKind* = enum
    vkInt, vkFloat, vkStr, vkBool, vkVoid, vkStruct, vkFun, vkArray, vkDict

  Value* = ref object
    case kind*: ValueKind
    of vkInt:    intVal*: int
    of vkFloat:  floatVal*: float
    of vkStr:    strVal*: string
    of vkBool:   boolVal*: bool
    of vkVoid:   discard
    of vkStruct:
      structType*: string
      fields*: Table[string, Value]
    of vkFun:
      funNode*: Node
      closure*: Env
    of vkArray:
      elements*: seq[Value]
    of vkDict:
      dictKeys*: seq[Value]
      dictVals*: seq[Value]

  Env* = ref object
    vars*: Table[string, Value]
    immutable*: Table[string, bool]
    parent*: Env

  ReturnException* = object of CatchableError
    value*: Value

# Function call callback — set by eval.nim at startup
var gCallFun*: proc(fn: Value, args: seq[Value], callLine: int): Value

proc newEnv*(parent: Env = nil): Env =
  Env(vars: initTable[string, Value](),
      immutable: initTable[string, bool](),
      parent: parent)

proc get*(env: Env, name: string): Value =
  if name in env.vars: return env.vars[name]
  if env.parent != nil: return env.parent.get(name)
  raise newException(ValueError, "Undefined variable: " & name)

proc set*(env: Env, name: string, val: Value, isLet: bool = false) =
  if name in env.immutable and env.immutable[name]:
    raise newException(ValueError, "Cannot reassign immutable variable: " & name)
  env.vars[name] = val
  env.immutable[name] = isLet

proc setExisting*(env: Env, name: string, val: Value) =
  if name in env.vars:
    if name in env.immutable and env.immutable[name]:
      raise newException(ValueError, "Cannot reassign immutable variable: " & name)
    env.vars[name] = val
    return
  if env.parent != nil:
    env.parent.setExisting(name, val)
    return
  raise newException(ValueError, "Undefined variable: " & name)

proc valueToStr*(v: Value): string =
  case v.kind
  of vkInt:    $v.intVal
  of vkFloat:  $v.floatVal
  of vkStr:    v.strVal
  of vkBool:   $v.boolVal
  of vkVoid:   ""
  of vkArray:
    var parts: seq[string] = @[]
    for e in v.elements: parts.add(valueToStr(e))
    "[" & parts.join(", ") & "]"
  of vkDict:
    var parts: seq[string] = @[]
    for i in 0 ..< v.dictKeys.len:
      parts.add(valueToStr(v.dictKeys[i]) & ": " & valueToStr(v.dictVals[i]))
    "[" & parts.join(", ") & "]"
  of vkStruct:
    var parts: seq[string] = @[]
    for k, val in v.fields: parts.add(k & ": " & valueToStr(val))
    v.structType & "[" & parts.join(", ") & "]"
  of vkFun: "<fun>"

proc interpolate*(s: string, env: Env): string =
  var result = ""
  var i = 0
  while i < s.len:
    if s[i] == '{':
      var j = i + 1
      while j < s.len and s[j] != '}': inc j
      let varName = s[i+1 ..< j]
      try:
        result &= valueToStr(env.get(varName))
      except:
        result &= "{" & varName & "}"
      i = j + 1
    else:
      result.add(s[i])
      inc i
  result
