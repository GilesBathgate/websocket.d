module websocket;

import std.socket;
import core.thread;
import linerange;

class WebSocketServer
{

    this(Address addr)
    {
        listener = new TcpSocket();
        listener.blocking = false;
        listener.bind(addr);
    }

    Fiber start()
    {
        listener.listen(10);
        return new Fiber(&loop);
    }

    void delegate(ubyte[]) onMessage;

private:

    static immutable newline = "\r\n"; // not platform dependent in http

    static struct NetworkRange
    {
        this(Client client)
        {
            this.client = client;
        }

        bool empty() @safe
        {
            return client.closed;
        }

        ubyte[] front() @safe
        {
            return data;
        }

        void popFront() @safe
        {
            if (!client.pending)
            {
                data.length = 0;
                return;
            }

            ubyte[8192] buffer;
            auto len = client.source.receive(buffer);
            switch (len)
            {
            case 0:
                data.length = 0;
                client.closed = true;
                return;
            case Socket.ERROR:
                if (wouldHaveBlocked())
                {
                    client.pending = false;
                    return;
                }
                throw new SocketException(lastSocketError);
            default:
                data = buffer[0 .. len].dup;
                break;
            }

            if (len < buffer.length)
                client.pending = false;
        }

        ubyte[] data;
        Client client;

    }

    static class Client
    {
        import std.array;

        this(Socket source)
        {
            this.source = source;
            range = NetworkRange(this);
        }

        void writeln(string line)
        {
            if(!writeBuffer.capacity)
                writeBuffer.reserve(8192);

            writeBuffer ~= line;
            writeln();
        }

        void writeln()
        {
             writeBuffer ~= newline;
        }

        void flush()
        {
            source.send(writeBuffer.data);
            writeBuffer.clear();
        }

        bool pending;
        bool closed;
        Socket source;
        NetworkRange range;
        Appender!(char[]) writeBuffer;
    }


    Client current()
    {
        scope set = new SocketSet(10);
        set.add(listener);
        foreach (r; clients.byKey)
            set.add(r);

        auto c = Socket.select(set, null, null, timeout);
        if (c <= 0)
            return null;

        if (set.isSet(listener))
        {
            auto source = listener.accept();
            clients[source] = new Client(source);
        }

        foreach (client; clients.byKeyValue) {
            if (client.key !is listener && set.isSet(client.key))
            {
                if(client.value.closed) {
                    clients.remove(client.key);
                } else {
                    client.value.pending = true;
                    return client.value;
                }
            }
        }

        return null;
    }

    void loop()
    {
        while (true)
        {
            auto client = current();
            if (client)
            {
                try
                {
                    handleClient(client);
                }
                catch (SocketException ex)
                {
                    clients.remove(client.source);
                }
            }
            Fiber.yield();
        }
    }

    void handleClient(Client client)
    {
        auto accept = parseHandshake(client);
        onMessage(cast(ubyte[])accept);
    }

    string parseHandshake(Client client)
    {
        string[string] headers;
        string requestMethod;
        foreach (line; client.range.byLine())
        {
            if (line == newline)
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

        if(websocketRequested(headers))
        {
            if(auto k = Headers.Sec_WebSocket_Key in headers)
            {
                string key = *k ~ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
                import std.digest.sha, std.base64;

                return  Base64.encode(sha1Of(key));
            }
        }

        return null;
    }

    bool websocketRequested(string[string] headers)
    {
        if(auto c = Headers.Connection in headers)
        if(auto u = Headers.Upgrade in headers)
            return *c == HeaderFields.Upgrade && *u == HeaderFields.WebSocket;

        return false;
    }

    enum Headers : string {
        Sec_WebSocket_Key = "sec-websocket-key",
        Connection = "connection",
        Upgrade = "upgrade",
    }

    enum HeaderFields : string {
        Upgrade = "Upgrade",
        WebSocket = "websocket"
    }

    TcpSocket listener;
    Client[Socket] clients;
    Duration timeout;
}

unittest {

    static bool client()
    {
        Socket sock = new TcpSocket(new InternetAddress("localhost", 4000));
        scope (exit)
            sock.close();

        auto client = new WebSocketServer.Client(sock);
        client.writeln("GET /chat HTTP/1.1");
        client.writeln("Host: server.example.com");
        client.writeln("Upgrade: websocket");
        client.writeln("Connection: Upgrade");
        client.writeln("Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==");
        client.writeln();
        client.flush();

        return true;

    }

    static void server()
    {
        auto sv = new WebSocketServer(new InternetAddress("localhost", 4000));
        bool running = true;
        sv.onMessage = (ubyte[] m)
        {
            if(m == cast(ubyte[])"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
                running = false;
        };
        auto f = sv.start();
        while (running)
        {
            f.call();
            Thread.sleep(10.msecs);
        }
    }

    import core.thread;
    new Thread(&server).start();
    Thread.sleep(1.seconds);

    auto connected = client();
    assert(connected);
}
