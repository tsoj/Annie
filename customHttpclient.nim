include httpclient

iterator requestStream*(
    client: HttpClient, url: string, httpMethod: HttpMethod, shouldStop: proc(): bool
): string =

    doAssert(not url.contains({'\c', '\L'}), "url shouldn't contain any newline characters")
    let url = parseUri(url)

    if url.scheme == "":
        raise newException(ValueError, "No uri scheme supplied.")

    if httpMethod in {HttpHead, HttpConnect}:
        raise newException(ValueError, "HttpMethod head and connect are not supported for streams")

    newConnection(client, url)
    debugEcho "Connected"

    var newHeaders: HttpHeaders

    newHeaders = client.headers.override(override = nil)
    # Only change headers if they have not been specified already
    if not newHeaders.hasKey("Content-Length"):
        newHeaders["Content-Length"] = "0"

    if not newHeaders.hasKey("user-agent") and client.userAgent.len > 0:
        newHeaders["User-Agent"] = client.userAgent

    let headerString = generateHeaders(url, httpMethod, newHeaders, client.proxy)
    
    client.socket.send(headerString)
    debugEcho "sent request"
    var line: string
      
    while not shouldStop():
        line = client.socket.recvLine
        debugEcho "got new line"
        if line == "":
            # We've been disconnected.
            break
        yield line