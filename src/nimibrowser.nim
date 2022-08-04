import httpClient, asyncdispatch, httpclient, strtabs, uri, strformat, strutils, os, httpcore
import marshal
import zippy
import puppy

export asyncdispatch, httpclient, uri, strformat, strutils, os, strtabs

const COOKIEJAR = "cookiejar"

type NimiBrowser* = ref object
  usePuppy*: bool
  currentUri: string
  cookies*: StringTableRef
  proxyUrl*: string
  allowCompression*: bool
  userAgent*: string
  persistCookies*: bool

const defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:73.0) Gecko/20100101 Firefox/73.0"

proc writeCookies(br: NimiBrowser) =
  ## persits cookies to disk
  if br.persistCookies:
    writeFile(COOKIEJAR, $$br.cookies)

# template doSetCookies() {.dirty.} =


proc setCookies(br: NimiBrowser, resp: AsyncResponse) =
  ## For nim AsyncHttpClient
  if not resp.headers.hasKey("set-cookie"): return
  for key, val in resp.headers.pairs:
    # doSetCookies() ## TODO remove copy paste
    if key.toLowerAscii == "set-cookie":
      var cookies = val.split(";", 1) # we dont need the rest
      var cookie = cookies[0]
      if cookie.contains("="):
        let parts = cookie.split("=")
        br.cookies[parts[0]] = parts[1].strip()
      else:
        br.cookies[cookie] = ""
  br.writeCookies()

proc setCookies(br: NimiBrowser, resp: puppy.common.Response) =
  ## For puppy
  # if not resp.headers.hasKey("set-cookie"): return
  let val = resp.headers["set-cookie"]
  if val.len == 0: return
  var cookies = val.split(";", 1) # we dont need the rest
  var cookie = cookies[0]
  if cookie.contains("="):
    let parts = cookie.split("=")
    br.cookies[parts[0]] = parts[1].strip()
  else:
    br.cookies[cookie] = ""
  br.writeCookies()

proc clearCookies*(br: NimiBrowser) =
  ## clears all cookies
  br.cookies.clear()
  if br.persistCookies:
    br.writeCookies()
    writeFile("cookiejar", $$br.cookies)

func setCrsfTokens(br: NimiBrowser, headers: HttpHeaders): HttpHeaders =
  result = headers
  if br.cookies.contains("XSRF-TOKEN"):
    result["X-XSRF-TOKEN"] = br.cookies["XSRF-TOKEN"]

func makeCookies(br: NimiBrowser): string =
  for key, val in br.cookies.pairs:
    if val != "": result.add fmt"{key}={val}; "
    else: result.add fmt" {key};"

func toHeader*(headerStr: string): HttpHeaders =
  ## parses a http header (or parts of it) and returns a `HttpHeaders` object
  ## good for copy and paste from man in the middle proxies (like burp)
  result = newHttpHeaders()
  for line in headerStr.splitLines(): # TODO split lines is not good enough to parse all headers (multiline headers)
    if line.isEmptyOrWhitespace(): continue
    let (k, v) = parseHeader(line)
    result[k] = v

proc uncompressedBody*(resp: AsyncResponse): Future[string] {.async.} =
  ## if the body is compressed AND `allowCompression = true` return the uncompressed version.
  ## else this proc is a no op.
  let contentEncodings = resp.headers.getOrDefault("content-encoding")
  if contentEncodings.len == 0:
    return (await resp.body)
  if contentEncodings == "gzip":
    let body = await resp.body
    return uncompress(body, dataFormat = dfGzip)
  elif contentEncodings == "deflate":
    let body = await resp.body
    return uncompress(body, dataFormat = dfDeflate)
  else:
    raise newException(ValueError, "unsupported compression format: " & contentEncodings[0])


proc request*(br: NimiBrowser, url: string | Uri, httpMethod: HttpMethod,
    body = "", headers = newHttpHeaders(), multipart: MultipartData = newMultipartData()): Future[AsyncResponse] {.async.} =
  var vheaders = newHttpHeaders()
  let cookieStr = br.makeCookies()
  if cookieStr != "":
    vheaders["cookie"] = cookieStr
  vheaders["User-Agent"] = br.userAgent
  vheaders["Accept-Language"] = "de,en-US;q=0.7,en;q=0.3"
  vheaders["Connection"] = "close"
  if br.currentUri != "":
    vheaders["Referer"] = br.currentUri
    vheaders["Origin"] = br.currentUri
  if br.allowCompression:
    vheaders["Accept-Encoding"] = "deflate, gzip"

  vheaders = br.setCrsfTokens(vheaders)

  # If the user provided some headers we respect them.
  for (key, val) in headers.pairs():
    vheaders[key] = val

  if br.usePuppy:
    if br.proxyUrl != "":
      # TODO puppy proxy support
      raise newException(ValueError, "nimibrowser with puppy does not support proxy yet!")
    if ($multipart) != "":
      raise newException(ValueError, "nimibrowser with puppy does not support multipart yet! Do it yourself in the body!!")

    var pheaders: seq[Header] = @[]
    for key, value in vheaders:
      pheaders.add Header(key: key, value: value)
      echo Header(key: key, value: value)

    let req = Request(
      url: url.parseUrl(),
      headers: pheaders,
      verb: $httpMethod,
      body: body
    )
    let res = fetch(req)
    br.currentUri = url
    br.setCookies(res)
    # fake the AsyncResponse
    var bodyStream = newFutureStream[string]()
    await bodyStream.write(res.body)
    bodyStream.complete
    result = AsyncResponse(
      version: $1, ## TODO ??
      status: $res.code,
      headers: newHttpHeaders(), ## TODO,
      bodyStream: bodyStream
    )
  else:
    var client: AsyncHttpClient
    if br.proxyUrl != "":
      client = newAsyncHttpClient(headers = vheaders, proxy = newProxy(br.proxyUrl))
    else:
      client = newAsyncHttpClient(headers = vheaders)
    result = await client.request($url, httpMethod = httpMethod, body = body, multipart = multipart)
    br.currentUri = url
    br.setCookies(result)


proc get*(br: NimiBrowser, url: string | Uri, body = "",
    headers = newHttpHeaders(), multipart: MultipartData = newMultipartData()): Future[AsyncResponse] {.async.} =
  return await br.request($url, HttpGet, body, headers)

proc post*(br: NimiBrowser, url: string | Uri, body = "",
    headers = newHttpHeaders(), multipart: MultipartData = newMultipartData()): Future[AsyncResponse] {.async.} =
  return await br.request($url, HttpPost, body, headers)

proc newNimiBrowser*(cookiejar = COOKIEJAR, persistCookies = true, usePuppy = false): NimiBrowser =
  var cookies: StringTableRef
  if fileExists(cookiejar):
    cookies = to[StringTableRef](readFile(cookiejar))
  else:
    cookies = newStringTable()
  result = NimiBrowser(
    cookies: cookies,
    userAgent: defaultUserAgent,
    persistCookies: persistCookies,
    usePuppy: usePuppy
  )

when isMainModule and true:
  var br = newNimiBrowser(usePuppy = true)
  br.allowCompression = true
  let head = toHeader("""
Host: blog.fefe.de
Sec-Ch-Ua: "Chromium";v="95", ";Not A Brand";v="99"
Sec-Ch-Ua-Mobile: ?0
Sec-Ch-Ua-Platform: "Windows"
Upgrade-Insecure-Requests: 1
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/95.0.4638.69 Safari/537.36
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.9
Sec-Fetch-Site: none
Sec-Fetch-Mode: navigate
Sec-Fetch-User: ?1
Sec-Fetch-Dest: document
Accept-Encoding: gzip, deflate
Accept-Language: de-DE,de;q=0.9,en-US;q=0.8,en;q=0.7
Connection: close
  """)
  echo head
  var resp = waitFor br.get("https://blog.fefe.de", headers = head)
  echo resp.headers
  # echo waitFor (resp.uncompressedBody())
  echo waitFor resp.body
