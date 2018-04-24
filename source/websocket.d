module websocket;

import std.socket;
import core.thread;

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

    static class Client
    {
        import std.array;

        this(Socket source)
        {
            this.source = source;
        }

        bool pending;
        bool closed;
        Socket source;
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
                    handleClient();
                }
                catch (SocketException ex)
                {
                    clients.remove(client.source);
                }
            }
            Fiber.yield();
        }
    }

    void handleClient()
    {
        onMessage([1]);
    }

    static bool client()
    {
        Socket sock = new TcpSocket(new InternetAddress("localhost", 4000));
        scope (exit)
            sock.close();
        return sock.isAlive();
    }

    static void server()
    {
        auto sv = new WebSocketServer(new InternetAddress("localhost", 4000));
        bool running = true;
        sv.onMessage = (ubyte[] m){ if(m[0] == 1) running = false; };
        auto f = sv.start();
        while (running)
        {
            f.call();
            Thread.sleep(10.msecs);
        }
    }

    TcpSocket listener;
    Client[Socket] clients;
    Duration timeout;
}

unittest {
    import core.thread;
    new Thread(&WebSocketServer.server).start();
    Thread.sleep(1.seconds);

    auto connected = WebSocketServer.client();
    assert(connected);
}
