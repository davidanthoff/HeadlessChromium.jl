"""
createPage(port::Int) -> String

Creates the proxy page attaching to the given WebSocket port (Julia side).
This page allows communication between Julia and the Chrome DevTools interface.
"""
function createPage(port::Int)
  tmppath = tempname() * ".html"

  open(tmppath, "w") do io
    Mustache.render(io, String(read(joinpath(@__DIR__, "wsproxy.html"))), port=port)
  end

  tmppath
end



"""
findfreeport([port_hint::Int]) -> Int

Finds the first available port on localhost.
"""
function findfreeport(porthint::Int=5000)
    xport, sock = listenany(porthint)
    close(sock)
    Int(xport)
end




"""
launchServer(outchan::Channel, inchan::Channel, port::Int)

Starts the WebSocket server that will send and receive messages from the
proxy page.
"""
function launchServer(outchan::Channel, inchan::Channel, port::Int)
  wsh = WebSocketHandler() do req,client

    @async begin  # listening loop
      DEBUG && info("starting inbound loop")
      while isopen(client) && isopen(inchan)
        try
          msg = String(read(client))
          put!(inchan, msg)
        catch e
          warn("error in reception loop : $e")
        end
      end
      DEBUG && info("exiting inbound loop (port $port)")
    end

    # outgoing message loop
    DEBUG && info("starting outbound loop")
    for m in outchan
      DEBUG && info("sending $m")
      try
        write(client, m)
      catch e
      end
    end

    DEBUG && info("exiting outbound loop (port $port)")
  end

  handler = HTTP.serve() do req::HTTP.Request
    rsp = HTTP.Response(100)
    rsp.headers["Access-Control-Allow-Origin"] = "http://localhost:8080"
    rsp.headers["Access-Control-Allow-Credentials"] = "true"
    rsp
  end

  handler.events["error"]  =
    (client, err) -> DEBUG ? println(err) : nothing
  handler.events["listen"] =
    (port) -> DEBUG ? println("Listening on $port...") : nothing

  server = Server(handler, wsh)
  @async run(server, port)
  server
end
