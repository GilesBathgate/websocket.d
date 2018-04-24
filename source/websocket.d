module websocket;

import std.socket;

class WebSocketServer
{
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
        auto listener = new TcpSocket();
        listener.bind(new InternetAddress(4000));
        listener.listen(10);
        auto client = listener.accept();
    }
}

unittest {
    import core.thread;
    new Thread(&WebSocketServer.server).start();
    auto connected = WebSocketServer.client();
    assert(connected);
}
