import std/[
    net,
    json,
    strutils,
    strformat,
    tables,
    os,
    options,
    random,
    httpclient,
    streams
]

import log

export HttpClient, HttpMethod

const maxNumRetries = 5

proc getRequestsSession*(): HttpClient =
    newHttpClient()

iterator streamEvents*(host: string, path: string, token: string): Option[JsonNode] =

    for i in 1..maxNumRetries:

        try:
            let s = newSocket()
            wrapSocket(newContext(), s)
            s.connect(host, Port(443))

            let req = &"GET {path} HTTP/1.1\r\nHost: {host}\r\nAuthorization: Bearer {token}\r\nAccept: x-ndjson\r\n\r\n"
            logDebug "Sending stream request: ", req

            s.send(req)
            while true:
                let line = s.recvLine(timeout = 15_000)
                logDebug line
                if line.strip.len > 0 and line.strip[0] == '{':
                    let json = line.parseJson
                    yield some json
                elif line.startsWith("HTTP/1.1 "):
                    let
                        words = line.splitWhitespace
                        status = if words.len >= 2: words[1].parseInt else: 418
                    if status == 200:
                        continue
                    elif status == 429:
                        logWarn "Rate limited."
                        sleep 60_000 + rand(0..10_000)
                        break
                    else:
                        
                        raise newException(IOError, &"Unexpected response.\nRequest: {req}\nStatus: {status}\nError: {line}")
                else:
                    # This is just a hack so that the loop gets a regular response, so that I don't need to do something multithreaded
                    yield none JsonNode

        except CatchableError:
            if i == maxNumRetries:
                raise
            logInfo "Retrying after getting an exception: ", getCurrentExceptionMsg()
            sleep 500

proc jsonResponse*(client: var HttpClient, httpMethod: HttpMethod, url: string, token: string, payload = initTable[string, string]()): JsonNode =

    client.headers = newHttpHeaders({
        "Authorization": "Bearer " & token,
        "Accept": "application/json",
        "Content-Type": "application/json"
    })

    let (body, status) = block:
        var
            body: string
            status: int
        for i in 1..maxNumRetries:
            try:                    
                let
                    response = client.request(url, httpMethod = httpMethod, body = $(%payload))
                    statusNumberStrings = response.status.splitWhitespace

                if statusNumberStrings.len == 0:
                    raise newException(IOError, "Unknown status code: " & response.status)

                status = statusNumberStrings[0].parseInt
                body = response.bodyStream.readAll
                
                if status == 429: # rate limited, should wait at least a minute
                    logWarn "Rate limited."
                    sleep 60_000 + rand(0..10_000)
                else:
                    break                    
            except Exception:
                if i == maxNumRetries:
                    raise
                logInfo "Retrying after getting an exception: ", getCurrentExceptionMsg()
                sleep 500
        (body, status)

    if status != 200:
        var errorMsg: string = ""
        try:
            errorMsg = body.parseJson{"error"}.getStr
        except JsonParsingError:
            errorMsg = body
        errorMsg = &"Unexpected response.\nURL: {url}\nStatus: {status}\nError: {errorMsg}"
        raise newException(IOError, errorMsg)

    result = body.parseJson

proc jsonResponse*(httpMethod: HttpMethod, query: string, token: string, payload = initTable[string, string]()): JsonNode =

    var client = getRequestsSession()
    try:
        client.jsonResponse(httpMethod, query, token, payload)
    finally:
        client.close()