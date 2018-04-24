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

private:

    void loop()
    {
        while(true)
        {
            listener.accept();
            Fiber.yield();
        }
    }

    static bool client()
    {
        auto domain = "localhost";
        ushort port = 4000;
        Socket sock = new TcpSocket(new InternetAddress(domain, port));
        scope (exit)
            sock.close();
        return sock.isAlive();
    }

    static void server()
    {
        auto sv = new WebSocketServer(new InternetAddress(4000));
        bool running = true;
        auto f = sv.start();
        while (running)
        {
            f.call();
            Thread.sleep(10.msecs);
            running = false;
        }
    }

    Socket listener;
}

unittest {
    import core.thread;
    new Thread(&WebSocketServer.server).start();
    Thread.sleep(1.seconds);

    auto connected = WebSocketServer.client();
    assert(connected);
}
