module server;

import std.socket;
import core.thread;
import std.string;
import linerange;
import client;
import frame;

class Server
{

    this(Address addr)
    {
        listener = new TcpSocket();
        listener.blocking = false;
        listener.bind(addr);
    }

    ~this()
    {
        shutdown();
    }

    void shutdown()
    {
        _running = false;
        listener.shutdown(SocketShutdown.BOTH);
        listener.close();
    }

    void start()
    {
        listener.listen(10);
        auto handler = new Fiber(&handleClient);
        _running = true;
        while (_running)
        {
            _client = current();
            if (_client)
            {
                handler.call();
            }
            Thread.sleep(10.msecs);
        }
    }

    void delegate(Client, ubyte[]) onMessage;

private:

    Client _client;
    bool _running;

    Client current()
    {
        scope set = new SocketSet(10);
        set.add(listener);
        foreach (r; clients.byKey)
            set.add(r);

        auto c = Socket.select(set, null, null, timeout);
        if (c <= 0)
            return _client;

        if (set.isSet(listener))
        {
            auto source = listener.accept();
            clients[source] = new Client(source);
        }

        foreach (client; clients.byKeyValue)
        {
            if (client.key !is listener && set.isSet(client.key))
            {
                if (client.value.closed)
                {
                    client.value.close();
                    clients.remove(client.key);
                }
                else
                {
                    client.value.pending = true;
                    return client.value;
                }
            }
        }

        return null;
    }

    void handleClient()
    {
        while (_running)
        {
            try
            {
                auto client = _client; //TODO;
                if (!client.socketUpgraded)
                {
                    auto accept = parseHandshake(client);
                    if (accept)
                    {
                        client.startHeader("HTTP/1.1 101 Switching Protocols");
                        client.writeHeader(Headers.Upgrade, "websocket");
                        client.writeHeader(Headers.Connection, "Upgrade");
                        client.writeHeader(Headers.Sec_WebSocket_Accept, accept);
                        client.endHeader();
                        client.flush();
                        client.socketUpgraded = true;
                    }
                }
                else
                {
                    foreach (f; client.range.byFrame())
                    {
                        switch (f.header.opcode)
                        {
                        case Opcodes.Text:
                            onMessage(client, f.payload());
                            break;
                        case Opcodes.Ping:
                            auto r = new Frame(0);
                            r.header.fin = true;
                            r.header.opcode = Opcodes.Pong;
                            client.source.send(r.data);
                            break;
                        case Opcodes.Pong:
                            auto r = new Frame(0);
                            r.header.fin = true;
                            r.header.opcode = Opcodes.Ping;
                            client.source.send(r.data);
                            break;
                        case Opcodes.Close:
                            auto r = new Frame(0);
                            r.header.fin = true;
                            r.header.opcode = Opcodes.Close;
                            client.source.send(r.data);
                            client.close();
                            clients.remove(client.source);
                            break;
                        default:
                            break;
                        }

                        Fiber.yield();
                    }
                }
                Fiber.yield();

            }
            catch (SocketException ex)
            {
                clients.remove(_client.source);
            }
        }
    }

    string parseHandshake(Client client)
    {
        string[string] headers;
        string requestMethod;
        foreach (line; client.range.byLine())
        {
            if (line == newLine)
                break;

            import std.algorithm;

            if (!requestMethod && line.canFind("GET"))
            {
                requestMethod = line;
            }
            else
            {
                auto pair = line.findSplit(":");
                import std.string;

                headers[pair[0].toLower] = pair[2].strip();
            }
            Fiber.yield();
        }

        if (websocketRequested(headers))
        {
            if (auto k = Headers.Sec_WebSocket_Key.toLower in headers)
            {
                string key = *k ~ GUID;
                import std.digest.sha, std.base64;

                return Base64.encode(sha1Of(key));
            }
        }

        return null;
    }

    bool websocketRequested(string[string] headers)
    {
        if (auto c = Headers.Connection.toLower in headers)
            if (auto u = Headers.Upgrade.toLower in headers)
                return *c == HeaderFields.Upgrade && *u == HeaderFields.WebSocket;

        return false;
    }

    enum Headers : string
    {
        Connection = "Connection",
        Upgrade = "Upgrade",
        Sec_WebSocket_Key = "Sec-WebSocket-Key",
        Sec_WebSocket_Accept = "Sec-WebSocket-Accept",
        Sec_WebSocket_Version = "Sec-WebSocket-Version"
    }

    enum HeaderFields : string
    {
        Upgrade = "Upgrade",
        WebSocket = "websocket"
    }

    enum GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

    TcpSocket listener;
    Client[Socket] clients;
    Duration timeout;
}

unittest
{
    static bool client()
    {
        import std.process;

        Thread.sleep(10.msecs);
        spawnProcess(["node", "test/websocketclient.js"]);

        return true;
    }

    static bool server()
    {
        auto sv = new Server(new InternetAddress("localhost", 4000));
        bool running = true;
        sv.onMessage = (Client c, ubyte[] m) {
            string msg = cast(immutable char[]) m;
            switch (msg)
            {
            case "Hello World!":
                c.sendText(msg); // Echo.
                break;
            case "Goodbye":
                c.sendText("Leaving so soon?");
                sv.shutdown();
                break;
            default:
                assert(0);
            }
        };
        sv.start();

        return true;
    }

    assert(client());
    assert(server());
}
