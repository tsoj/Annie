import std/[
    json,
    strutils,
    strformat,
    tables,
    os
]

import nimpy

import log

export PyObject


let
    requests = pyImport("requests")
    py = pyBuiltinsModule()

proc getRequestsSession*(): PyObject =
    requests.Session()

iterator streamEvents*(url: string, token: string): JsonNode =
    {. warning[BareExcept]:off .}
    try:
        let response = requests.get(
            url = url,
            headers = {"Authorization": fmt"Bearer {token}", "Accept": "x-ndjson"}.toTable,
            stream = true,
            timeout = 15
        )

        let lines = response.iter_lines()
        while true:
            let line = py.next(lines).to(string)
            if line.strip.len > 0 and line.strip[0] == '{':
                let json = line.parseJson
                yield json
    except CatchableError:
        raise
    except Exception:
        # doing this because nimpy sometimes raises a pure Exception
        raise newException(CatchableError, getCurrentExceptionMsg())
    {. warning[BareExcept]:on .}

type HttpMethod* = enum
    httpPost, httpGet

proc jsonResponse*(session: PyObject, httpMethod: HttpMethod, url: string, token: string, payload = initTable[string, string]()): JsonNode =
    {. warning[BareExcept]:off .}
    try:
        let headers = {
            "Authorization": "Bearer " & token,
            "Accept": "application/json"
        }.toTable

        let (body, status) = block:
            var
                body: string
                status: int
            while true:
                let response = case httpMethod:
                    of httpGet: session.get(url, headers = headers, data = payload, timeout = 5)
                    of httpPost: session.post(url, headers = headers, data = payload, timeout = 5)

                status = response.status_code.to(int)
                body = response.content.to(string)
                
                if status == 429: # rate limited, should wait at least a minute
                    sleep 70_000
                else:
                    break
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
    except CatchableError:
        raise
    except Exception:
        # doing this because nimpy sometimes raises a pure Exception
        raise newException(CatchableError, getCurrentExceptionMsg())
    {. warning[BareExcept]:on .}

proc jsonResponse*(httpMethod: HttpMethod, query: string, token: string): JsonNode =
    let session = getRequestsSession()
    session.jsonResponse(httpMethod, query, token)