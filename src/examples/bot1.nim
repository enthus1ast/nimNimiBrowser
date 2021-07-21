import ../nimibrowser.nim
import asyncdispatch, tables, strtabs, os,
  strutils, uri, httpcore, httpclient


var br = newNimiBrowser()
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
