# eval.nim
# Tree-walk interpreter

import ast, tables, strutils, os, threadpool
import eval_types
import modules/nv
import modules/fs
import modules/task
import modules/http

export eval_types

proc evalNode*(node: Node, env: Env): Value

proc callFun*(fn: Value, args: seq[Value], callLine: int): Value =
  if fn.kind != vkFun:
    raise newException(ValueError, "Line " & $callLine & ": not a function")
  let fnode = fn.funNode
  var callEnv = newEnv(fn.closure)
  for i, param in fnode.params:
    callEnv.set(param.paramName, if i < args.len: args[i] else: Value(kind: vkVoid))
  try:
    discard evalNode(fnode.body, callEnv)
  except ReturnException as e:
    return e.value
  Value(kind: vkVoid)

# Register callFun globally so modules (task, etc.) can call it
gCallFun = callFun

proc evalArgs(nodes: seq[Node], env: Env): seq[Value] =
  for n in nodes: result.add(evalNode(n, env))

proc isTruthy(v: Value): bool =
  case v.kind
  of vkBool:  v.boolVal
  of vkInt:   v.intVal != 0
  of vkFloat: v.floatVal != 0.0
  of vkStr:   v.strVal.len > 0
  of vkVoid:  false
  else: true

proc evalNode*(node: Node, env: Env): Value =
  case node.kind

  of nkProgram, nkBlock:
    var last = Value(kind: vkVoid)
    for s in node.stmts: last = evalNode(s, env)
    last

  of nkPragma, nkImport, nkFromImport:
    Value(kind: vkVoid)

  of nkFunDecl:
    env.set(node.funName, Value(kind: vkFun, funNode: node, closure: env))
    Value(kind: vkVoid)

  of nkStructDecl:
    env.vars[node.structName] = Value(kind: vkVoid)
    Value(kind: vkVoid)

  of nkDestructDecl:
    let val = evalNode(node.destructVal, env)
    if val.kind == vkArray:
      for i, name in node.destructNames:
        if name == "_": continue
        let v = if i < val.elements.len: val.elements[i] else: Value(kind: vkVoid)
        env.set(name, v, isLet = node.isLet)
    else:
      raise newException(ValueError, "Cannot destructure non-array value")
    Value(kind: vkVoid)

  of nkVarDecl:
    # Array destructuring: var [a, b] = expr  stored as varName = "__destructure__a,b"
    if node.varName.startsWith("__destructure__"):
      let names = node.varName[15..^1].split(',')
      let val = evalNode(node.varVal, env)
      if val.kind == vkArray:
        for i, name in names:
          let v = if i < val.elements.len: val.elements[i] else: Value(kind: vkVoid)
          env.set(name, v, isLet = false)
      return Value(kind: vkVoid)
    env.set(node.varName, evalNode(node.varVal, env), isLet = false)
    Value(kind: vkVoid)

  of nkLetDecl:
    if node.varName.startsWith("__destructure__"):
      let names = node.varName[15..^1].split(',')
      let val = evalNode(node.varVal, env)
      if val.kind == vkArray:
        for i, name in names:
          let v = if i < val.elements.len: val.elements[i] else: Value(kind: vkVoid)
          env.set(name, v, isLet = true)
      return Value(kind: vkVoid)
    env.set(node.varName, evalNode(node.varVal, env), isLet = true)
    Value(kind: vkVoid)

  of nkReturn:
    let val = evalNode(node.expr, env)
    var ex = newException(ReturnException, "return")
    ex.value = val
    raise ex

  of nkExprStmt: evalNode(node.expr, env)

  of nkAssign:
    let val = evalNode(node.assignVal, env)
    env.setExisting(node.assignTarget, val)
    val

  of nkWhile:
    while isTruthy(evalNode(node.whileCond, env)):
      discard evalNode(node.whileBody, env)
    Value(kind: vkVoid)

  of nkForIn:
    let iterVal = evalNode(node.forIter, env)
    let loopEnv = newEnv(env)
    case iterVal.kind
    of vkArray:
      for i, v in iterVal.elements:
        if node.forIdxVar != "": loopEnv.set(node.forIdxVar, Value(kind: vkInt, intVal: i))
        if node.forValVar != "": loopEnv.set(node.forValVar, v)
        discard evalNode(node.forBody, loopEnv)
    of vkDict:
      for i in 0 ..< iterVal.dictKeys.len:
        if node.forIdxVar != "": loopEnv.set(node.forIdxVar, iterVal.dictKeys[i])
        if node.forValVar != "": loopEnv.set(node.forValVar, iterVal.dictVals[i])
        discard evalNode(node.forBody, loopEnv)
    of vkStr:
      for i, c in iterVal.strVal:
        if node.forIdxVar != "": loopEnv.set(node.forIdxVar, Value(kind: vkInt, intVal: i))
        if node.forValVar != "": loopEnv.set(node.forValVar, Value(kind: vkStr, strVal: $c))
        discard evalNode(node.forBody, loopEnv)
    else: raise newException(ValueError, "Cannot iterate over " & $iterVal.kind)
    Value(kind: vkVoid)

  of nkForRange:
    let loopEnv = newEnv(env)
    var i = evalNode(node.rangeFrom, env).intVal
    let stop = evalNode(node.rangeTo, env).intVal
    while i <= stop:
      loopEnv.set(node.rangeVar, Value(kind: vkInt, intVal: i))
      discard evalNode(node.rangeBody, loopEnv)
      inc i
    Value(kind: vkVoid)

  of nkIntLit:   Value(kind: vkInt,   intVal:   node.intVal)
  of nkFloatLit: Value(kind: vkFloat, floatVal: node.floatVal)
  of nkStrLit:   Value(kind: vkStr,   strVal:   node.strVal)
  of nkBoolLit:  Value(kind: vkBool,  boolVal:  node.boolVal)

  of nkArrayLit:
    var elems: seq[Value] = @[]
    for e in node.elements: elems.add(evalNode(e, env))
    Value(kind: vkArray, elements: elems)

  of nkDictLit:
    var keys, vals: seq[Value] = @[]
    for p in node.pairs:
      keys.add(evalNode(p.pairKey, env))
      vals.add(evalNode(p.pairVal, env))
    Value(kind: vkDict, dictKeys: keys, dictVals: vals)

  of nkIdent:   env.get(node.name)

  of nkIndex:
    let obj = evalNode(node.indexObj, env)
    let key = evalNode(node.indexKey, env)
    case obj.kind
    of vkArray: obj.elements[key.intVal]
    of vkDict:
      let ks = valueToStr(key)
      for i, k in obj.dictKeys:
        if valueToStr(k) == ks: return obj.dictVals[i]
      raise newException(ValueError, "Key not found: " & ks)
    else: raise newException(ValueError, "Cannot index " & $obj.kind)

  of nkStructLit:
    var fields = initTable[string, Value]()
    for fi in node.fieldInits:
      fields[fi.fieldName] = evalNode(fi.fieldVal, env)
    Value(kind: vkStruct, structType: node.structType, fields: fields)

  of nkDotAccess:
    let obj = evalNode(node.dotObj, env)
    if obj.kind == vkStruct and node.dotField in obj.fields:
      return obj.fields[node.dotField]
    raise newException(ValueError, "No field: " & node.dotField)

  of nkBinOp:
    let l = evalNode(node.left, env)
    let r = evalNode(node.right, env)
    case node.op
    of "+":
      if l.kind == vkInt and r.kind == vkInt: Value(kind: vkInt, intVal: l.intVal + r.intVal)
      elif l.kind == vkStr or r.kind == vkStr: Value(kind: vkStr, strVal: valueToStr(l) & valueToStr(r))
      else: Value(kind: vkFloat, floatVal: (if l.kind == vkFloat: l.floatVal else: float(l.intVal)) + (if r.kind == vkFloat: r.floatVal else: float(r.intVal)))
    of "-":
      if l.kind == vkInt and r.kind == vkInt: Value(kind: vkInt, intVal: l.intVal - r.intVal)
      else: Value(kind: vkFloat, floatVal: (if l.kind == vkFloat: l.floatVal else: float(l.intVal)) - (if r.kind == vkFloat: r.floatVal else: float(r.intVal)))
    of "*":
      if l.kind == vkInt and r.kind == vkInt: Value(kind: vkInt, intVal: l.intVal * r.intVal)
      else: Value(kind: vkFloat, floatVal: (if l.kind == vkFloat: l.floatVal else: float(l.intVal)) * (if r.kind == vkFloat: r.floatVal else: float(r.intVal)))
    of "/": Value(kind: vkFloat, floatVal: (if l.kind == vkFloat: l.floatVal else: float(l.intVal)) / (if r.kind == vkFloat: r.floatVal else: float(r.intVal)))
    of "==": Value(kind: vkBool, boolVal: valueToStr(l) == valueToStr(r))
    of "!=": Value(kind: vkBool, boolVal: valueToStr(l) != valueToStr(r))
    of "<":  Value(kind: vkBool, boolVal: l.intVal < r.intVal)
    of ">":  Value(kind: vkBool, boolVal: l.intVal > r.intVal)
    of "<=": Value(kind: vkBool, boolVal: l.intVal <= r.intVal)
    of ">=": Value(kind: vkBool, boolVal: l.intVal >= r.intVal)
    else: Value(kind: vkVoid)

  of nkUnOp:
    let v = evalNode(node.expr, env)
    if v.kind == vkBool: Value(kind: vkBool, boolVal: not v.boolVal)
    elif v.kind == vkInt: Value(kind: vkInt, intVal: -v.intVal)
    else: v

  of nkCall:
    callFun(evalNode(node.callee, env), evalArgs(node.args, env), node.line)

  of nkMethodCall:
    if node.obj.kind == nkIdent:
      let modName = node.obj.name
      let meth    = node.methodName
      let args    = evalArgs(node.callArgs, env)
      case modName
      of "nv":   return callNv(meth, args, env)
      of "fs":   return callFs(meth, args)
      of "task": return callTask(meth, args, node.line)
      of "http": return callHttp(meth, args)
      else: discard

    let obj  = evalNode(node.obj, env)
    let args = evalArgs(node.callArgs, env)

    # File handle
    if obj.kind == vkStruct and obj.structType == "__file":
      return callFileHandle(node.methodName, valueToStr(obj.fields["__path"]), args)

    # URL handle
    if obj.kind == vkStruct and obj.structType == "__url":
      return callUrlHandle(node.methodName, obj, args)

    # User-defined method
    callFun(env.get(node.methodName), @[obj] & args, node.line)

  of nkParam, nkStructField, nkDictPair:
    Value(kind: vkVoid)
