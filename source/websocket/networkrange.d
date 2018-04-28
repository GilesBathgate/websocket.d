module networkrange;

import std.socket;
import client;

struct NetworkRange
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
