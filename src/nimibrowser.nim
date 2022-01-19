import httpClient, asyncdispatch, httpclient, strtabs, uri, strformat, strutils, os
import marshal
import zippy

export asyncdispatch, httpclient, uri, strformat, strutils, os, strtabs

const COOKIEJAR = "cookiejar"

type NimiBrowser* = ref object
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

proc setCookies(br: NimiBrowser, resp: AsyncResponse) =
  if not resp.headers.hasKey("set-cookie"): return
  for key, val in resp.headers.pairs:
    if key.toLowerAscii == "set-cookie":
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

proc setCrsfTokens(br: NimiBrowser, headers: HttpHeaders): HttpHeaders =
  result = headers
  if br.cookies.contains("XSRF-TOKEN"):
    result["X-XSRF-TOKEN"] = br.cookies["XSRF-TOKEN"]

proc makeCookies(br: NimiBrowser): string =
  for key, val in br.cookies.pairs:
    if val != "": result.add fmt"{key}={val}; "
    else: result.add fmt" {key};"

proc setHeaderIfMissing*(headers: HttpHeaders, key, value: string) =
  ## sets a header if it is not here

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


proc request*(br: NimiBrowser, url: string, httpMethod: HttpMethod,
    body = "", headers = newHttpHeaders(), multipart: MultipartData = newMultipartData()): Future[AsyncResponse] {.async.} =
  var vheaders = newHttpHeaders()
  vheaders["cookie"] = br.makeCookies()
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

  var client: AsyncHttpClient
  if br.proxyUrl != "":
    client = newAsyncHttpClient(headers = vheaders, proxy = newProxy(br.proxyUrl))
  else:
    client = newAsyncHttpClient(headers = vheaders)
  result = await client.request(url, httpMethod = httpMethod, body = body, multipart = multipart)
  br.currentUri = url
  br.setCookies(result)


proc get*(br: NimiBrowser, url: string, body = "",
    headers = newHttpHeaders(), multipart: MultipartData = newMultipartData()): Future[AsyncResponse] {.async.} =
  return await br.request(url, HttpGet, body, headers)

proc post*(br: NimiBrowser, url: string, body = "",
    headers = newHttpHeaders(), multipart: MultipartData = newMultipartData()): Future[AsyncResponse] {.async.} =
  return await br.request(url, HttpPost, body, headers)

proc newNimiBrowser*(cookiejar = COOKIEJAR, persistCookies = true): NimiBrowser =
  var cookies: StringTableRef
  if fileExists(cookiejar):
    cookies = to[StringTableRef](readFile(cookiejar))
  else:
    cookies = newStringTable()
  result = NimiBrowser(
    cookies: cookies,
    userAgent: defaultUserAgent,
    persistCookies: persistCookies
  )

when isMainModule and false:
  var br = newNimiBrowser()
  br.allowCompression = true
  var resp = waitFor br.get("https://blog.fefe.de")
  echo resp.headers
  echo waitFor (resp.uncompressedBody())
