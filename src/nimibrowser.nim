import httpClient, asyncdispatch, httpclient, strtabs, uri, strformat, strutils, os
import marshal
import zippy


type NimiBrowser* = ref object
  currentUri: string
  cookies: StringTableRef
  defaultHeaders: HttpHeaders
  proxyUrl*: string
  allowCompression*: bool

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
  # "content-encoding": @["gzip"]
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


proc request*(br: NimiBrowser, url: string, httpMethod: HttpMethod, body = "", headers = newHttpHeaders()): Future[AsyncResponse] {.async.} =
  var vheaders = headers # TODO FIRST set our defaults, then let the user overwrite with their headers, to allow fully custom requests
  # br.cookies["__cfduid"] = "d5c917d143c948487c3f578ee899c566d1585589665"
  vheaders["cookie"] = br.makeCookies()
  vheaders["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:73.0) Gecko/20100101 Firefox/73.0"
  vheaders["Accept-Language"] = "de,en-US;q=0.7,en;q=0.3"
  vheaders["Connection"] = "close"
  if br.currentUri != "":
    vheaders["Referer"] = br.currentUri
    vheaders["Origin"] = br.currentUri
  if br.allowCompression:
    vheaders["Accept-Encoding"] = "deflate, gzip"

  vheaders = br.setCrsfTokens(vheaders)

  var client: AsyncHttpClient
  if br.proxyUrl != "":
    client = newAsyncHttpClient(headers = vheaders, proxy = newProxy(br.proxyUrl))
  else:
    client = newAsyncHttpClient(headers = vheaders)
  result = await client.request(url, httpMethod = httpMethod, body = body)
  br.currentUri = url
  br.setCookies(result)

proc get*(br: NimiBrowser, url: string, body = "", headers = newHttpHeaders()): Future[AsyncResponse] {.async.} =
  return await br.request(url, HttpGet, body, headers)

proc post*(br: NimiBrowser, url: string, body = "", headers = newHttpHeaders()): Future[AsyncResponse] {.async.} =
  return await br.request(url, HttpPost, body, headers)

proc newNimiBrowser*(): NimiBrowser =
  var cookies: StringTableRef
  if fileExists("cookiejar"):
    cookies = to[StringTableRef](readFile("cookiejar"))
  else:
    cookies = newStringTable()
  result = NimiBrowser(
    cookies: cookies
    # defaultHeaders: defaultHeaders
  )

proc iAmFirefox(br: var NimiBrowser) =
  ## sets default header like firefox


when isMainModule:
  var br = newNimiBrowser()
  br.allowCompression = true
  var resp = waitFor br.get("https://blog.fefe.de")
  echo resp.headers
  echo waitFor (resp.uncompressedBody())

when isMainModule and false:
  var br = newNimiBrowser(
    # defaultHeaders: newHttpHeaders
  )
  br.iAmFirefox()
  br.proxyUrl = "http://127.0.0.1:8080"
  var resp = waitFor br.get("https://beta.pathofdiablo.com/trade-search")
  echo br.cookies

  sleep(2000)
  proc search(br: NimiBrowser, item: string): string =
    let body = """{"searchFilter":{"item":["$$$NAME$$$"],"need":"","quality":["All"],"gameMode":"softcore","poster":"","onlineOnly":false,"properties":[{"comparitor":"*"}]}}""".replace("$$$NAME$$$", item)
    var headers = newHttpHeaders({
      "Accept": "application/json, text/plain, */*",
      "Content-Type": "application/json;charset=utf-8",
      "sec-fetch-dest": "empty",
      "sec-fetch-mode": "cors",
      "sec-fetch-site": "same-origin",

    })
    resp = waitFor br.post("https://beta.pathofdiablo.com/api/v2/trade/search", body = body, headers = headers)
    let js = waitFor resp.body
    echo resp.status
    return js


  echo "UP:", (waitFor br.get("https://beta.pathofdiablo.com/api/account/get_updates")).code

  writeFile("cont.html", br.search("Aldur"))
  sleep(4000)

  echo "UP:", (waitFor br.get("https://beta.pathofdiablo.com/api/account/get_updates")).code
  writeFile("cont2.html", br.search("Windforce"))
  sleep(4000)



  if true: quit()
  # block:

  #   let header = newHttpHeaders(
  #     {
  #       "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:73.0) Gecko/20100101 Firefox/73.0",
  #       "Accept": "application/json, text/plain, */*",
  #       "Accept-Language": "de,en-US;q=0.7,en;q=0.3",
  #       # "Accept-Encoding": "gzip, deflate",
  #       "Content-Type": "application/json;charset=utf-8",
  #       "Origin": "https://beta.pathofdiablo.com",
  #       "Connection": "close",
  #       "Referer": "https://beta.pathofdiablo.com/"
  #     }
  #   )
  #   var client = newAsyncHttpClient(headers = header)
  #   echo (waitFor client.request("https://beta.pathofdiablo.com/trade-search")).headers




  # )
  # var client = newAsyncHttpClient(headers = header)
  # let body = """{"searchFilter":{"item":["Jah rune"],"need":"","quality":["All"],"gameMode":"softcore","poster":"","onlineOnly":false,"properties":[{"comparitor":"*"}]}}"""
  # echo waitFor client.postContent("http://beta.pathofdiablo.com/api/v2/trade/search", body = body)




