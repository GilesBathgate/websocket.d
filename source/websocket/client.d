module client;

import std.socket;
import networkrange;
import frame;

static immutable newLine = "\r\n"; // not platform dependent in http

class Client
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
        writeBuffer ~= newLine;
    }

    void writeHeader(string field, string value)
    {
        writeBuffer ~= field;
        writeBuffer ~= ": ";
        writeBuffer ~= value;
        writeBuffer ~= newLine;
    }

    void endHeader()
    {
        writeBuffer ~= newLine;
    }

    void flush()
    {
        source.send(writeBuffer.data);
        writeBuffer.clear();
    }

    void close()
    {
        source.shutdown(SocketShutdown.BOTH);
        source.close();
    }

    void sendText(string text)
    {
        auto f = new Frame(text.length);
        f.header.fin = true;
        f.header.opcode = Opcodes.Text;
        f.payload = cast(ubyte[]) text;
        source.send(f.data);
    }

    bool socketUpgraded;
    bool pending;
    bool closed;
    Socket source;
    NetworkRange range;
    Appender!(char[]) writeBuffer;
}
