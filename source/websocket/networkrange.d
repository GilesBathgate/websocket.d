module networkrange;

import std.socket;
import client;

@safe struct NetworkRange
{

    this(Client client, size_t bufferSize = 8192)
    {
        this.client = client;
        this.buffer = new ubyte[bufferSize];
    }

    bool empty()
    {
        return client.closed;
    }

    ubyte[] front()
    {
        return buffer[0 .. length];
    }

    void popFront()
    {
        if (!client.pending)
        {
            length = 0;
            return;
        }

        length = client.source.receive(buffer);
        switch (length)
        {
        case 0:
            length = 0;
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
            break;
        }

        recieved += length;

        if (length < buffer.length)
            client.pending = false;
    }

    ubyte[] buffer;
    size_t length;
    Client client;
    size_t recieved;
}
