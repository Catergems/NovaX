import strutils
import lexer, ast

type
  Parser* = object
    tokens*: seq[Token]
    pos*: int

proc newParser*(tokens: seq[Token]): Parser =
  Parser(tokens: tokens, pos: 0)

proc peek(p: Parser, offset: int = 0): Token =
  let i = p.pos + offset
  if i < p.tokens.len: p.tokens[i]
  else: Token(kind: tkEOF, value: "", line: 0)

proc current(p: Parser): Token = p.peek(0)

proc advance(p: var Parser): Token =
  result = p.tokens[p.pos]
  inc p.pos

proc skipNewlines(p: var Parser) =
  while p.current().kind in {tkNewline, tkSemicolon}:
    discard p.advance()

proc eat(p: var Parser, kind: TokenKind): Token =
  p.skipNewlines()
  if p.current().kind == kind:
    return p.advance()
  else:
    raise newException(ValueError,
      "Line " & $p.current().line & ": expected " & $kind &
      " but got " & $p.current().kind & " (" & p.current().value & ")")

proc parseExpr(p: var Parser): Node
proc parseStmt(p: var Parser): Node
proc parseBlock(p: var Parser): Node

proc parseArgs(p: var Parser): seq[Node] =
  discard p.eat(tkLParen)
  var args: seq[Node] = @[]
  p.skipNewlines()
  while p.current().kind != tkRParen:
    args.add(p.parseExpr())
    p.skipNewlines()
    if p.current().kind == tkComma: discard p.advance()
    p.skipNewlines()
  discard p.eat(tkRParen)
  args

proc parseBracketCollection(p: var Parser, line: int): Node =
  # Peek ahead to determine if array or dict
  # Dict: [ "key" : value, ... ]
  # Array: [ expr, expr, ... ]
  discard p.eat(tkLBracket)
  p.skipNewlines()

  if p.current().kind == tkRBracket:
    discard p.advance()
    return Node(kind: nkArrayLit, line: line, elements: @[])

  # Look ahead: if first non-newline token after first expr is ':', it's a dict
  let savedPos = p.pos
  # try parse first expr, then check for colon
  var isDict = false
  var scanPos = p.pos
  # simple heuristic: if current token is string/ident and next meaningful token is colon
  var sp = p.pos
  while sp < p.tokens.len and p.tokens[sp].kind in {tkNewline, tkSemicolon}: inc sp
  let firstKind = if sp < p.tokens.len: p.tokens[sp].kind else: tkEOF
  var sp2 = sp + 1
  while sp2 < p.tokens.len and p.tokens[sp2].kind in {tkNewline, tkSemicolon}: inc sp2
  let secondKind = if sp2 < p.tokens.len: p.tokens[sp2].kind else: tkEOF
  if firstKind in {tkString, tkIdent} and secondKind == tkColon:
    isDict = true

  if isDict:
    var pairs: seq[Node] = @[]
    while p.current().kind != tkRBracket:
      p.skipNewlines()
      let key = p.parseExpr()
      discard p.eat(tkColon)
      let val = p.parseExpr()
      pairs.add(Node(kind: nkDictPair, line: line, pairKey: key, pairVal: val))
      p.skipNewlines()
      if p.current().kind == tkComma: discard p.advance()
      p.skipNewlines()
    discard p.eat(tkRBracket)
    return Node(kind: nkDictLit, line: line, pairs: pairs)
  else:
    var elements: seq[Node] = @[]
    while p.current().kind != tkRBracket:
      p.skipNewlines()
      elements.add(p.parseExpr())
      p.skipNewlines()
      if p.current().kind == tkComma: discard p.advance()
      p.skipNewlines()
    discard p.eat(tkRBracket)
    return Node(kind: nkArrayLit, line: line, elements: elements)

proc parsePrimary(p: var Parser): Node =
  p.skipNewlines()
  let tok = p.current()
  case tok.kind
  of tkInt:
    discard p.advance()
    return Node(kind: nkIntLit, line: tok.line, intVal: parseInt(tok.value))
  of tkFloat:
    discard p.advance()
    return Node(kind: nkFloatLit, line: tok.line, floatVal: parseFloat(tok.value))
  of tkString:
    discard p.advance()
    return Node(kind: nkStrLit, line: tok.line, strVal: tok.value)
  of tkBool:
    discard p.advance()
    return Node(kind: nkBoolLit, line: tok.line, boolVal: tok.value == "true")
  of tkLBracket:
    return p.parseBracketCollection(tok.line)
  of tkIdent:
    discard p.advance()
    var node = Node(kind: nkIdent, line: tok.line, name: tok.value)
    # struct literal: ident[ field: val, ... ]
    if p.current().kind == tkLBracket:
      discard p.advance()
      var fields: seq[Node] = @[]
      p.skipNewlines()
      while p.current().kind != tkRBracket:
        let fname = p.eat(tkIdent).value
        discard p.eat(tkColon)
        let fval = p.parseExpr()
        fields.add(Node(kind: nkStructField, line: tok.line,
                        fieldName: fname, fieldVal: fval))
        p.skipNewlines()
        if p.current().kind in {tkComma, tkSemicolon}: discard p.advance()
        p.skipNewlines()
      discard p.eat(tkRBracket)
      return Node(kind: nkStructLit, line: tok.line,
                  structType: tok.value, fieldInits: fields)
    # dot chain
    while p.current().kind == tkDot:
      discard p.advance()
      let field = p.eat(tkIdent).value
      if p.current().kind == tkLParen:
        let args = p.parseArgs()
        node = Node(kind: nkMethodCall, line: tok.line,
                    obj: node, methodName: field, callArgs: args)
      else:
        node = Node(kind: nkDotAccess, line: tok.line,
                    dotObj: node, dotField: field)
    # plain call
    if p.current().kind == tkLParen:
      let args = p.parseArgs()
      node = Node(kind: nkCall, line: tok.line, callee: node, args: args)
      while p.current().kind == tkDot:
        discard p.advance()
        let field = p.eat(tkIdent).value
        if p.current().kind == tkLParen:
          let args2 = p.parseArgs()
          node = Node(kind: nkMethodCall, line: tok.line,
                      obj: node, methodName: field, callArgs: args2)
        else:
          node = Node(kind: nkDotAccess, line: tok.line,
                      dotObj: node, dotField: field)
    return node
  of tkLParen:
    discard p.advance()
    let inner = p.parseExpr()
    discard p.eat(tkRParen)
    return inner
  else:
    raise newException(ValueError,
      "Line " & $tok.line & ": unexpected token in expr: " & $tok.kind & " (" & tok.value & ")")

proc parseUnary(p: var Parser): Node =
  if p.current().kind == tkBang or p.current().kind == tkMinus:
    let tok = p.advance()
    let e = p.parseUnary()
    return Node(kind: nkUnOp, line: tok.line, expr: e)
  parsePrimary(p)

proc parseMulDiv(p: var Parser): Node =
  var left = p.parseUnary()
  while p.current().kind in {tkStar, tkSlash}:
    let op = p.advance().value
    let right = p.parseUnary()
    left = Node(kind: nkBinOp, line: left.line, op: op, left: left, right: right)
  left

proc parseAddSub(p: var Parser): Node =
  var left = p.parseMulDiv()
  while p.current().kind in {tkPlus, tkMinus}:
    let op = p.advance().value
    let right = p.parseMulDiv()
    left = Node(kind: nkBinOp, line: left.line, op: op, left: left, right: right)
  left

proc parseComparison(p: var Parser): Node =
  var left = p.parseAddSub()
  while p.current().kind in {tkEq, tkNeq, tkLt, tkGt, tkLte, tkGte}:
    let op = p.advance().value
    let right = p.parseAddSub()
    left = Node(kind: nkBinOp, line: left.line, op: op, left: left, right: right)
  left

proc parseExpr(p: var Parser): Node =
  p.parseComparison()

proc parseType(p: var Parser): string =
  case p.current().kind
  of tkIntType:   discard p.advance(); "int"
  of tkFloatType: discard p.advance(); "float"
  of tkStrType:   discard p.advance(); "str"
  of tkBoolType:  discard p.advance(); "bool"
  of tkIdent:     p.advance().value
  else: ""

proc parseParams(p: var Parser): seq[Node] =
  discard p.eat(tkLParen)
  var params: seq[Node] = @[]
  p.skipNewlines()
  while p.current().kind != tkRParen:
    let name = p.eat(tkIdent).value
    discard p.eat(tkColon)
    let t = p.parseType()
    params.add(Node(kind: nkParam, line: p.current().line,
                    paramName: name, paramType: t))
    p.skipNewlines()
    if p.current().kind == tkComma: discard p.advance()
    p.skipNewlines()
  discard p.eat(tkRParen)
  params

proc parseBlock(p: var Parser): Node =
  let line = p.current().line
  discard p.eat(tkLBrace)
  var stmts: seq[Node] = @[]
  p.skipNewlines()
  while p.current().kind != tkRBrace and p.current().kind != tkEOF:
    stmts.add(p.parseStmt())
    p.skipNewlines()
  discard p.eat(tkRBrace)
  Node(kind: nkBlock, line: line, stmts: stmts)

proc parseStmt(p: var Parser): Node =
  p.skipNewlines()
  let tok = p.current()
  case tok.kind
  of tkPragma:
    discard p.advance()
    return Node(kind: nkPragma, line: tok.line, pragmaVal: tok.value)
  of tkSemicolon, tkNewline:
    discard p.advance()
    return Node(kind: nkPragma, line: tok.line, pragmaVal: "")
  of tkFrom:
    discard p.advance()
    let path = p.eat(tkString).value
    discard p.eat(tkImport)
    let name = p.eat(tkString).value
    return Node(kind: nkFromImport, line: tok.line,
                fromPath: path, importName: name)
  of tkImport:
    discard p.advance()
    var path = ""
    if p.current().kind == tkString:
      path = p.advance().value
    else:
      path = p.eat(tkIdent).value
      while p.current().kind == tkSlash:
        discard p.advance()
        if p.current().kind == tkIdent:
          path &= "/" & p.advance().value
    return Node(kind: nkImport, line: tok.line,
                importPath: path, importAlias: "")
  of tkFun:
    discard p.advance()
    let name = p.eat(tkIdent).value
    let params = p.parseParams()
    var retType = ""
    if p.current().kind == tkColon:
      discard p.advance()
      retType = p.parseType()
    let body = p.parseBlock()
    return Node(kind: nkFunDecl, line: tok.line,
                funName: name, params: params, retType: retType, body: body)
  of tkVar:
    discard p.advance()
    p.skipNewlines()
    if p.current().kind == tkLBracket:
      discard p.advance()
      var names: seq[string] = @[]
      p.skipNewlines()
      while p.current().kind != tkRBracket:
        let n = if p.current().kind == tkUnderscore:
                  discard p.advance(); "_"
                else: p.eat(tkIdent).value
        names.add(n)
        p.skipNewlines()
        if p.current().kind == tkComma: discard p.advance()
        p.skipNewlines()
      discard p.eat(tkRBracket)
      discard p.eat(tkAssign)
      let val = p.parseExpr()
      return Node(kind: nkDestructDecl, line: tok.line,
                  isLet: false, destructNames: names, destructVal: val)
    let name = p.eat(tkIdent).value
    var t = ""
    if p.current().kind == tkColon:
      discard p.advance()
      t = p.parseType()
    discard p.eat(tkAssign)
    let val = p.parseExpr()
    return Node(kind: nkVarDecl, line: tok.line,
                varName: name, varType: t, varVal: val)
  of tkLet:
    discard p.advance()
    p.skipNewlines()
    if p.current().kind == tkLBracket:
      discard p.advance()
      var names: seq[string] = @[]
      p.skipNewlines()
      while p.current().kind != tkRBracket:
        let n = if p.current().kind == tkUnderscore:
                  discard p.advance(); "_"
                else: p.eat(tkIdent).value
        names.add(n)
        p.skipNewlines()
        if p.current().kind == tkComma: discard p.advance()
        p.skipNewlines()
      discard p.eat(tkRBracket)
      discard p.eat(tkAssign)
      let val = p.parseExpr()
      return Node(kind: nkDestructDecl, line: tok.line,
                  isLet: true, destructNames: names, destructVal: val)
    let name = p.eat(tkIdent).value
    var t = ""
    if p.current().kind == tkColon:
      discard p.advance()
      t = p.parseType()
    discard p.eat(tkAssign)
    let val = p.parseExpr()
    return Node(kind: nkLetDecl, line: tok.line,
                varName: name, varType: t, varVal: val)
  of tkReturn:
    discard p.advance()
    let val = p.parseExpr()
    return Node(kind: nkReturn, line: tok.line, expr: val)
  of tkStruct:
    discard p.advance()
    let name = p.eat(tkIdent).value
    discard p.eat(tkLBracket)
    var fields: seq[Node] = @[]
    p.skipNewlines()
    while p.current().kind != tkRBracket:
      let fname = p.eat(tkIdent).value
      discard p.eat(tkColon)
      let ftype = p.parseType()
      fields.add(Node(kind: nkParam, line: tok.line,
                      paramName: fname, paramType: ftype))
      p.skipNewlines()
      if p.current().kind in {tkComma, tkSemicolon}: discard p.advance()
      p.skipNewlines()
    discard p.eat(tkRBracket)
    return Node(kind: nkStructDecl, line: tok.line,
                structName: name, fields: fields)
  of tkFor:
    discard p.advance()
    # for i,v in collection { }  or  for i = start..end { }
    let firstName = if p.current().kind == tkUnderscore:
                      discard p.advance(); ""
                    else: p.eat(tkIdent).value
    if p.current().kind == tkComma:
      # for i,v in ...
      discard p.advance()
      let valName = if p.current().kind == tkUnderscore:
                      discard p.advance(); ""
                    else: p.eat(tkIdent).value
      discard p.eat(tkIn)
      let iter = p.parseExpr()
      let body = p.parseBlock()
      return Node(kind: nkForIn, line: tok.line,
                  forIdxVar: firstName, forValVar: valName,
                  forIter: iter, forBody: body)
    elif p.current().kind == tkIn:
      # for v in collection (no index)
      discard p.advance()
      let iter = p.parseExpr()
      let body = p.parseBlock()
      return Node(kind: nkForIn, line: tok.line,
                  forIdxVar: "", forValVar: firstName,
                  forIter: iter, forBody: body)
    elif p.current().kind == tkAssign:
      # for i = start..end { }
      discard p.advance()
      let fromExpr = p.parseExpr()
      discard p.eat(tkDotDot)
      let toExpr = p.parseExpr()
      let body = p.parseBlock()
      return Node(kind: nkForRange, line: tok.line,
                  rangeVar: firstName, rangeFrom: fromExpr,
                  rangeTo: toExpr, rangeBody: body)
    else:
      raise newException(ValueError,
        "Line " & $tok.line & ": malformed for loop")
  of tkWhile:
    discard p.advance()
    let cond = p.parseExpr()
    let body = p.parseBlock()
    return Node(kind: nkWhile, line: tok.line, whileCond: cond, whileBody: body)
  else:
    # ident = expr reassignment check
    if tok.kind == tkIdent:
      var scanPos = p.pos + 1  # p.pos points at tok (not yet consumed)
      while scanPos < p.tokens.len and p.tokens[scanPos].kind in {tkNewline, tkSemicolon}:
        inc scanPos
      if scanPos < p.tokens.len and p.tokens[scanPos].kind == tkAssign:
        discard p.advance()          # consume ident
        discard p.advance()          # consume = (no eat, avoid skipNewlines swallowing things)
        let val = p.parseExpr()
        return Node(kind: nkAssign, line: tok.line,
                    assignTarget: tok.value, assignVal: val)
    let e = p.parseExpr()
    return Node(kind: nkExprStmt, line: tok.line, expr: e)

proc parse*(tokens: seq[Token]): Node =
  var p = newParser(tokens)
  var stmts: seq[Node] = @[]
  p.skipNewlines()
  while p.current().kind != tkEOF:
    stmts.add(p.parseStmt())
    p.skipNewlines()
  Node(kind: nkProgram, line: 0, stmts: stmts)
