import strutils
import os, lexer, parser, ast, eval, threadpool

proc hasPragmaNoMain(node: Node): bool =
  if node.kind == nkProgram:
    for s in node.stmts:
      if s.kind == nkPragma and "0xN0P" in s.pragmaVal:
        return true
  false

proc runFile(path: string) =
  if not fileExists(path):
    stderr.writeLine("Error: file not found: " & path)
    quit(1)

  let src = readFile(path)
  var tokens: seq[Token]
  try:
    tokens = tokenize(src)
  except Exception as e:
    stderr.writeLine("Lexer error in " & path & ": " & e.msg)
    quit(1)

  var tree: Node
  try:
    tree = parse(tokens)
  except Exception as e:
    stderr.writeLine("Parse error in " & path & ": " & e.msg)
    quit(1)

  let noMain = hasPragmaNoMain(tree)
  let env = newEnv()

  env.set("nv", Value(kind: vkVoid))
  env.set("fs", Value(kind: vkVoid))
  env.set("task", Value(kind: vkVoid))
  env.set("http", Value(kind: vkVoid))
  env.set("isexisted", Value(kind: vkBool, boolVal: true))
  env.set("true", Value(kind: vkBool, boolVal: true))
  env.set("false", Value(kind: vkBool, boolVal: false))

  try:
    if noMain:
      discard evalNode(tree, env)
    else:
      discard evalNode(tree, env)
      let mainFn = env.get("main")
      discard callFun(mainFn, @[], 0)
  except Exception as e:
    stderr.writeLine("Runtime error in " & path & ": " & e.msg)
    quit(1)

  sync()

when isMainModule:
  if paramCount() < 1:
    stderr.writeLine("Usage: nvx <file.nvx>")
    quit(1)
  runFile(paramStr(1))
