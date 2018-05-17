module server;

import std.socket;
import core.thread;
import std.string;
import linerange;
import client;
import frame;
import message;

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
        _running = true;
        while (_running)
        {
            _client = current();
            if (_client)
            {
                _client.handler.call();
            }
            Thread.sleep(10.msecs);
        }
    }

    void delegate(Message) onMessage;
    void delegate(Client) onNewConnection;

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
            auto newClient = new Client(source, new Fiber(&handleClient));
            clients[source] = newClient;
            if (onNewConnection)
                onNewConnection(newClient);
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
                if (!_client.socketUpgraded)
                {
                    auto accept = parseHandshake(_client);
                    if (accept)
                        switchProtocol(_client, accept);
                }
                else
                {
                    parseFrames(_client);
                }
                Fiber.yield();
            }
            catch (SocketException ex)
            {
                clients.remove(_client.source);
            }
        }
    }

    void switchProtocol(Client client, string accept)
    {
        client.startHeader("HTTP/1.1 101 Switching Protocols");
        client.writeHeader(Headers.Upgrade, HeaderFields.WebSocket);
        client.writeHeader(Headers.Connection, HeaderFields.Upgrade);
        client.writeHeader(Headers.Sec_WebSocket_Accept, accept);
        client.endHeader();
        client.flush();
        client.socketUpgraded = true;
    }

    void parseFrames(Client client)
    {
        auto range = client.range;
        foreach (f; range.byFrame())
        {
            switch (f.header.opcode)
            {
            case Opcodes.Text:
                if (onMessage)
                    onMessage(Message(client, Message.Type.Text, f.payload()));
                break;
            case Opcodes.Binary:
                if (onMessage)
                    onMessage(Message(client, Message.Type.Binary, f.payload()));
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

    string parseHandshake(Client client)
    {
        string[string] headers;
        string requestMethod;
        auto range = client.range;
        foreach (line; range.byLine())
        {
            if (range.recieved >= 8192)
                throw new SocketException("Header too large");

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
            enum Sec_WebSocket_Key = Headers.Sec_WebSocket_Key.toLower;
            if (auto k = Sec_WebSocket_Key in headers)
            {
                return createKey(*k);
            }
        }

        return null;
    }

    static string createKey(string key)
    {
        import std.digest.sha, std.base64;

        return Base64.encode(sha1Of(key ~ GUID));
    }

    unittest
    {
        auto k = "dGhlIHNhbXBsZSBub25jZQ==";
        auto r = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=";
        assert(createKey(k) == r);
    }

    bool websocketRequested(string[string] headers)
    {
        enum Connection = Headers.Connection.toLower;
        enum Upgrade = Headers.Upgrade.toLower;
        if (auto c = Connection in headers)
            if (auto u = Upgrade in headers)
                return compare(*c, HeaderFields.Upgrade)
                    && compare(*u, HeaderFields.WebSocket);

        return false;
    }

    static bool compare(string a, string b)
    {
        return a.toLower == b.toLower;
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

