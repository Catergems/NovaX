type
  NodeKind* = enum
    # Declarations
    nkProgram, nkFunDecl, nkVarDecl, nkLetDecl, nkStructDecl,
    nkParam, nkImport, nkFromImport, nkPragma, nkDestructDecl,
    # Statements
    nkBlock, nkReturn, nkExprStmt,
    # For loops
    nkForIn,      # for i,v in collection { }
    nkForRange,   # for i = 1..100 { }
    nkWhile,      # while cond { }
    # Expressions
    nkCall, nkMethodCall, nkDotAccess, nkAssign,
    nkBinOp, nkUnOp, nkIdent, nkIndex,
    # Literals
    nkIntLit, nkFloatLit, nkStrLit, nkBoolLit,
    nkArrayLit, nkDictLit, nkDictPair,
    # Struct
    nkStructLit, nkStructField

  Node* = ref object
    line*: int
    case kind*: NodeKind
    of nkProgram, nkBlock:
      stmts*: seq[Node]
    of nkFunDecl:
      funName*: string
      params*: seq[Node]
      retType*: string
      body*: Node
    of nkParam:
      paramName*: string
      paramType*: string
    of nkVarDecl, nkLetDecl:
      varName*: string
      varType*: string
      varVal*: Node
    of nkDestructDecl:
      isLet*: bool
      destructNames*: seq[string]
      destructVal*: Node
    of nkStructDecl:
      structName*: string
      fields*: seq[Node]
    of nkStructLit:
      structType*: string
      fieldInits*: seq[Node]
    of nkStructField:
      fieldName*: string
      fieldVal*: Node
    of nkImport:
      importPath*: string
      importAlias*: string
    of nkFromImport:
      fromPath*: string
      importName*: string
    of nkPragma:
      pragmaVal*: string
    of nkReturn, nkExprStmt, nkUnOp:
      expr*: Node
    of nkCall:
      callee*: Node
      args*: seq[Node]
    of nkMethodCall:
      obj*: Node
      methodName*: string
      callArgs*: seq[Node]
    of nkDotAccess:
      dotObj*: Node
      dotField*: string
    of nkAssign:
      assignTarget*: string
      assignVal*: Node
    of nkBinOp:
      op*: string
      left*: Node
      right*: Node
    of nkIndex:
      indexObj*: Node
      indexKey*: Node
    of nkIdent:
      name*: string
    of nkIntLit:
      intVal*: int
    of nkFloatLit:
      floatVal*: float
    of nkStrLit:
      strVal*: string
    of nkBoolLit:
      boolVal*: bool
    of nkArrayLit:
      elements*: seq[Node]
    of nkDictLit:
      pairs*: seq[Node]
    of nkDictPair:
      pairKey*: Node
      pairVal*: Node
    of nkForIn:
      forIdxVar*: string   # i  (or "" if _)
      forValVar*: string   # v  (or "" if _)
      forIter*: Node
      forBody*: Node
    of nkForRange:
      rangeVar*: string
      rangeFrom*: Node
      rangeTo*: Node
      rangeBody*: Node
    of nkWhile:
      whileCond*: Node
      whileBody*: Node
