type
  TokenKind* = enum
    # Literals
    tkInt, tkFloat, tkString, tkBool, tkIdent,
    # Keywords
    tkFun, tkLet, tkVar, tkReturn, tkImport, tkFrom, tkStruct, tkFor, tkIn, tkWhile,
    # Types
    tkIntType, tkFloatType, tkStrType, tkBoolType,
    # Symbols
    tkLParen, tkRParen, tkLBrace, tkRBrace, tkLBracket, tkRBracket,
    tkComma, tkColon, tkSemicolon, tkDot, tkDotDot, tkAssign, tkPlus, tkMinus,
    tkStar, tkSlash, tkBang, tkEq, tkNeq, tkLt, tkGt, tkLte, tkGte,
    tkArrow, tkUnderscore,
    # Special
    tkPragma, tkNewline, tkEOF

  Token* = object
    kind*: TokenKind
    value*: string
    line*: int

  Lexer* = object
    src*: string
    pos*: int
    line*: int

proc newLexer*(src: string): Lexer =
  Lexer(src: src, pos: 0, line: 1)

proc peek(l: Lexer, offset: int = 0): char =
  let i = l.pos + offset
  if i < l.src.len: l.src[i] else: '\0'

proc advance(l: var Lexer): char =
  result = l.src[l.pos]
  inc l.pos
  if result == '\n': inc l.line

proc skipWhitespace(l: var Lexer) =
  while l.pos < l.src.len and l.peek() in {' ', '\t', '\r'}:
    discard l.advance()

proc skipLineComment(l: var Lexer) =
  while l.pos < l.src.len and l.peek() != '\n':
    discard l.advance()

proc skipBlockComment(l: var Lexer) =
  while l.pos < l.src.len:
    let c = l.advance()
    if c == '*' and l.peek() == '/':
      discard l.advance()
      break

proc readString(l: var Lexer, delim: char): string =
  var s = ""
  while l.pos < l.src.len:
    let c = l.advance()
    if c == delim: break
    s.add(c)
  s

proc readTripleString(l: var Lexer): string =
  var s = ""
  while l.pos < l.src.len - 2:
    if l.peek(0) == '"' and l.peek(1) == '"' and l.peek(2) == '"':
      discard l.advance(); discard l.advance(); discard l.advance()
      break
    s.add(l.advance())
  s

proc readNumber(l: var Lexer, first: char): (TokenKind, string) =
  var s = $first
  var isFloat = false
  while l.pos < l.src.len and (l.peek() in {'0'..'9'} or (l.peek() == '.' and l.peek(1) != '.')):
    let c = l.advance()
    if c == '.': isFloat = true
    s.add(c)
  if isFloat: (tkFloat, s) else: (tkInt, s)

proc readIdent(l: var Lexer, first: char): string =
  var s = $first
  while l.pos < l.src.len and (l.peek() in {'a'..'z','A'..'Z','0'..'9','_'}):
    s.add(l.advance())
  s

proc keyword(s: string): TokenKind =
  case s
  of "fun": tkFun
  of "let": tkLet
  of "var": tkVar
  of "return": tkReturn
  of "import": tkImport
  of "from": tkFrom
  of "struct": tkStruct
  of "for": tkFor
  of "in": tkIn
  of "while": tkWhile
  of "true", "false": tkBool
  of "int": tkIntType
  of "float": tkFloatType
  of "str": tkStrType
  of "bool": tkBoolType
  else: tkIdent

proc tokenize*(src: string): seq[Token] =
  var l = newLexer(src)
  var tokens: seq[Token] = @[]

  template tok(k: TokenKind, v: string) =
    tokens.add(Token(kind: k, value: v, line: l.line))

  while l.pos < l.src.len:
    l.skipWhitespace()
    if l.pos >= l.src.len: break

    let line = l.line
    let c = l.advance()

    case c
    of '\n':
      tok(tkNewline, "\\n")
    of '#':
      var s = "#"
      while l.pos < l.src.len and l.peek() != '\n':
        s.add(l.advance())
      tok(tkPragma, s)
    of '/':
      if l.peek() == '/':
        discard l.advance()
        l.skipLineComment()
      elif l.peek() == '*':
        discard l.advance()
        l.skipBlockComment()
      else:
        tok(tkSlash, "/")
    of '"':
      if l.peek(0) == '"' and l.peek(1) == '"':
        discard l.advance(); discard l.advance()
        let s = l.readTripleString()
        tok(tkString, s)
      else:
        let s = l.readString('"')
        tok(tkString, s)
    of '(':  tok(tkLParen, "(")
    of ')':  tok(tkRParen, ")")
    of '{':  tok(tkLBrace, "{")
    of '}':  tok(tkRBrace, "}")
    of '[':  tok(tkLBracket, "[")
    of ']':  tok(tkRBracket, "]")
    of ',':  tok(tkComma, ",")
    of ':':  tok(tkColon, ":")
    of ';':  tok(tkSemicolon, ";")
    of '.':
      if l.peek() == '.':
        discard l.advance()
        tok(tkDotDot, "..")
      else:
        tok(tkDot, ".")
    of '+':  tok(tkPlus, "+")
    of '-':
      if l.peek() == '>':
        discard l.advance()
        tok(tkArrow, "->")
      else:
        tok(tkMinus, "-")
    of '*':  tok(tkStar, "*")
    of '=':
      if l.peek() == '=':
        discard l.advance()
        tok(tkEq, "==")
      else:
        tok(tkAssign, "=")
    of '!':
      if l.peek() == '=':
        discard l.advance()
        tok(tkNeq, "!=")
      else:
        tok(tkBang, "!")
    of '<':
      if l.peek() == '=':
        discard l.advance()
        tok(tkLte, "<=")
      else:
        tok(tkLt, "<")
    of '>':
      if l.peek() == '=':
        discard l.advance()
        tok(tkGte, ">=")
      else:
        tok(tkGt, ">")
    of '_':
      if l.pos < l.src.len and l.peek() in {'a'..'z','A'..'Z','0'..'9','_'}:
        let s = l.readIdent('_')
        tokens.add(Token(kind: tkIdent, value: s, line: line))
      else:
        tok(tkUnderscore, "_")
    of '0'..'9':
      let (kind, val) = l.readNumber(c)
      tokens.add(Token(kind: kind, value: val, line: line))
    of 'a'..'z', 'A'..'Z':
      let s = l.readIdent(c)
      let k = keyword(s)
      tokens.add(Token(kind: k, value: s, line: line))
    else:
      discard

  tok(tkEOF, "")
  tokens
