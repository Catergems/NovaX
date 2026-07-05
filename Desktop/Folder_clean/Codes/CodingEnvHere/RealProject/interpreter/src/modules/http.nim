# modules/http.nim
# net/http module for nvx

import ../eval_types, tables, httpclient, strutils

proc makeResponse(resp: Response): Value =
  var dataFields = initTable[string, Value]()
  dataFields["body"]       = Value(kind: vkStr, strVal: resp.body)
  dataFields["status"]     = Value(kind: vkStr, strVal: $resp.status)
  dataFields["statusCode"] = Value(kind: vkInt, intVal: resp.code.int)
  dataFields["ok"]         = Value(kind: vkBool, boolVal: resp.code.int >= 200 and resp.code.int < 300)
  return Value(kind: vkStruct, structType: "Response", fields: dataFields)

proc makeError(msg: string): Value =
  var dataFields = initTable[string, Value]()
  dataFields["body"]       = Value(kind: vkStr, strVal: "")
  dataFields["status"]     = Value(kind: vkStr, strVal: "error")
  dataFields["statusCode"] = Value(kind: vkInt, intVal: 0)
  dataFields["ok"]         = Value(kind: vkBool, boolVal: false)
  return Value(kind: vkStruct, structType: "Response", fields: dataFields)

proc callHttp*(meth: string, args: seq[Value]): Value =
  case meth
  of "url":
    let urlStr = if args.len > 0: valueToStr(args[0]) else: ""
    var fields = initTable[string, Value]()
    fields["__url"]     = Value(kind: vkStr, strVal: urlStr)
    fields["__timeout"] = Value(kind: vkInt, intVal: 30000)
    fields["__headers"] = Value(kind: vkDict,
                            dictKeys: @[Value(kind: vkStr, strVal: "User-Agent")],
                            dictVals: @[Value(kind: vkStr, strVal: "nvx-interpreter/1.0")])
    return Value(kind: vkStruct, structType: "__url", fields: fields)
  else:
    raise newException(ValueError, "http has no method: " & meth)

proc buildClient(urlStruct: Value): HttpClient =
  var client = newHttpClient()
  # Apply timeout
  if "__timeout" in urlStruct.fields:
    client.timeout = urlStruct.fields["__timeout"].intVal
  # Apply headers
  if "__headers" in urlStruct.fields:
    let h = urlStruct.fields["__headers"]
    if h.kind == vkDict:
      var headers: seq[(string, string)] = @[]
      for i in 0 ..< h.dictKeys.len:
        headers.add((valueToStr(h.dictKeys[i]), valueToStr(h.dictVals[i])))
      client.headers = newHttpHeaders(headers)
  return client

proc callUrlHandle*(meth: string, urlStruct: Value, args: seq[Value]): Value =
  let url = valueToStr(urlStruct.fields["__url"])
  case meth
  of "get":
    var client = buildClient(urlStruct)
    try:
      let resp = client.get(url)
      return Value(kind: vkArray, elements: @[makeResponse(resp), Value(kind: vkStr, strVal: "ok")])
    except Exception as e:
      return Value(kind: vkArray, elements: @[makeError(e.msg), Value(kind: vkStr, strVal: e.msg)])

  of "post":
    var client = buildClient(urlStruct)
    let body = if args.len > 0: valueToStr(args[0]) else: ""
    try:
      let resp = client.post(url, body = body)
      return Value(kind: vkArray, elements: @[makeResponse(resp), Value(kind: vkStr, strVal: "ok")])
    except Exception as e:
      return Value(kind: vkArray, elements: @[makeError(e.msg), Value(kind: vkStr, strVal: e.msg)])

  of "put":
    var client = buildClient(urlStruct)
    let body = if args.len > 0: valueToStr(args[0]) else: ""
    try:
      let resp = client.put(url, body = body)
      return Value(kind: vkArray, elements: @[makeResponse(resp), Value(kind: vkStr, strVal: "ok")])
    except Exception as e:
      return Value(kind: vkArray, elements: @[makeError(e.msg), Value(kind: vkStr, strVal: e.msg)])

  of "patch":
    var client = buildClient(urlStruct)
    let body = if args.len > 0: valueToStr(args[0]) else: ""
    try:
      let resp = client.patch(url, body = body)
      return Value(kind: vkArray, elements: @[makeResponse(resp), Value(kind: vkStr, strVal: "ok")])
    except Exception as e:
      return Value(kind: vkArray, elements: @[makeError(e.msg), Value(kind: vkStr, strVal: e.msg)])

  of "delete":
    var client = buildClient(urlStruct)
    try:
      let resp = client.delete(url)
      return Value(kind: vkArray, elements: @[makeResponse(resp), Value(kind: vkStr, strVal: "ok")])
    except Exception as e:
      return Value(kind: vkArray, elements: @[makeError(e.msg), Value(kind: vkStr, strVal: e.msg)])

  of "head":
    var client = buildClient(urlStruct)
    try:
      let resp = client.head(url)
      return Value(kind: vkArray, elements: @[makeResponse(resp), Value(kind: vkStr, strVal: "ok")])
    except Exception as e:
      return Value(kind: vkArray, elements: @[makeError(e.msg), Value(kind: vkStr, strVal: e.msg)])

  of "setHeader":
    # url.setHeader("key", "val") -> returns modified url struct
    let key = if args.len > 0: valueToStr(args[0]) else: ""
    let val = if args.len > 1: valueToStr(args[1]) else: ""
    var h = urlStruct.fields["__headers"]
    h.dictKeys.add(Value(kind: vkStr, strVal: key))
    h.dictVals.add(Value(kind: vkStr, strVal: val))
    urlStruct.fields["__headers"] = h
    return urlStruct

  of "setTimeout":
    let ms = if args.len > 0 and args[0].kind == vkInt: args[0].intVal
             elif args.len > 0 and args[0].kind == vkFloat: int(args[0].floatVal)
             else: 30000
    urlStruct.fields["__timeout"] = Value(kind: vkInt, intVal: ms)
    return urlStruct

  else:
    raise newException(ValueError, "url handle has no method: " & meth)
