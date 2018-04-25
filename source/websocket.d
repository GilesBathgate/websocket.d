module websocket;

import std.socket;
import core.thread;
import linerange;
import std.string;

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
            writeBuffer.reserve(8192);
        }

        void startHeader(string line)
        {
            writeBuffer ~= line;
            writeBuffer ~= newline;
        }

        void writeHeader(string field, string value)
        {
            writeBuffer ~= field;
            writeBuffer ~= ": ";
            writeBuffer ~= value;
            writeBuffer ~= newline;
        }

        void endHeader()
        {
            writeBuffer ~= newline;
        }

        void flush()
        {
            source.send(writeBuffer.data);
            writeBuffer.clear();
        }

        bool socketUpgraded;
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

        foreach (client; clients.byKeyValue)
        {
            if (client.key !is listener && set.isSet(client.key))
            {
                if (client.value.closed)
                {
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
        if(!client.socketUpgraded) {
            auto accept = parseHandshake(client);
            if(accept)
            {
                client.startHeader("HTTP/1.1 101 Switching Protocols");
                client.writeHeader(Headers.Upgrade, "websocket");
                client.writeHeader(Headers.Connection, "Upgrade");
                client.writeHeader(Headers.Sec_WebSocket_Accept, accept);
                client.endHeader();
                client.flush();
                client.socketUpgraded = true;
            }
        } else {
            client.range.popFront();
            auto msg = client.range.front;
            if(!msg)
                return;

            auto m = cast(Message*)msg;
            auto length = m.length;
            while(msg.length < length)
            {
                client.range.popFront();
                msg ~= client.range.front;

                Fiber.yield();
            }

            switch(m.opcode)
            {
                case Opcodes.Text:
                    onMessage(m.payload());
                    break;
                default:
                    break;
            }
        }
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

    enum Opcodes : ubyte
    {
        Continue = 0,
        Text = 1,
        Binary = 2, // 3, 4, 5, 6, 7 Reserved
        Close = 8,
        Ping = 9,
        Pong = 10 // 11,12,13,14,15 Reserved
    }

    static struct Message
    {
        static assert(this.sizeof == 10);
        align(1):
        import std.bitmanip;
        mixin(bitfields!(
            Opcodes, "opcode", 4,
            bool,    "rsv3",   1,
            bool,    "rsv2",   1,
            bool,    "rsv1",   1,
            bool,    "fin",    1,
            ubyte,   "len",    7,
            bool,    "masked", 1));
        ubyte[2] len16;
        ubyte[6] len64;

        uint offset() @safe
        {
            switch(len)
            {
                case 0x7E:
                    return 4;
                case 0x7F:
                    return 10;
                default:
                    return 2;
            }
        }

        @property {
            size_t length() @safe
            {
                auto length = len;
                switch(length)
                {
                    case 0x7E:
                        return bigEndianToNative!ushort(len16);
                    case 0x7F:
                        ubyte[8] loong = len16 ~ len64;
                        return cast(size_t)bigEndianToNative!ulong(loong);
                    default:
                        return length;
                }
            }

            void length(size_t length) @safe
            {
                if(length < 0x7E)
                {
                    len = cast(ubyte)length;
                }
            }
        }

        ubyte[] payload()
        {
            auto self = cast(ubyte*)&this;
            auto o = offset();
            auto l = length();
            if (masked)
            {
                enum maskLength = uint.sizeof;
                auto d = o + maskLength;
                auto mask = self[o .. d];
                auto data = self[d .. d + l];

                foreach(i, ref b; data)
                    b = b ^ mask[i % maskLength];

                return data;
            } else {
                return self[o .. o + l];
            }
        }

        ubyte[] payload(ubyte[] data)
        {
            auto self = cast(ubyte*)&this;
            auto l = data.length;
            length = l;
            auto o = offset();
            ubyte[] buffer = new ubyte[o + l];
            buffer[0 .. o] = self[0 .. o];
            buffer[o .. o + l] = data;
            return buffer;
        }
    }


    enum Headers : string
    {
        Connection = "Connection",
        Upgrade = "Upgrade",
        Sec_WebSocket_Key = "Sec-WebSocket-Key",
        Sec_WebSocket_Accept = "Sec-WebSocket-Accept"
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
    static void client()
    {
        import std.process;
        Thread.sleep(1.seconds);
        spawnProcess(["node", "test/websocketclient.js"]);
    }

    static bool server()
    {
        auto sv = new WebSocketServer(new InternetAddress("localhost", 4000));
        bool running = true;
        sv.onMessage = (ubyte[] m) {
            assert(cast(char[])m == "Hello World!");
            running = false;
        };
        auto f = sv.start();
        while (running)
        {
            f.call();
            Thread.sleep(10.msecs);
        }

        return true;
    }

    new Thread(&client).start();

    assert(server());
}
