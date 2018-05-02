module frame;

import std.traits;
import std.range;
import core.thread;
import std.bitmanip;

enum Opcodes : ubyte
{
    Continue = 0,
    Text = 1,
    Binary = 2, // 3, 4, 5, 6, 7 Reserved
    Close = 8,
    Ping = 9,
    Pong = 10 // 11,12,13,14,15 Reserved
}

FrameRange!R byFrame(R, S = ReturnType!((R r) => r.front))(R range)
if (isInputRange!(Unqual!R) && isInputRange!S)
{
    return FrameRange!R(range);
}

struct FrameRange(T)
if (is(ReturnType!((T r) => r.front) : void[]))
{
    this(T range)
    {
        this.range = range;
        popFront();
    }

    bool empty()
    {
        return range.empty;
    }

    Frame front()
    {
        return frame;
    }

    void popFront()
    {
        auto length = getLength();
        while (chunk.length < length)
        {
            Fiber.yield();

            chunk ~= range.front;
            if (!range.empty)
                range.popFront();

            length = getLength();
        }

        chunk = chunk[length .. $];
    }

    size_t getLength()
    {
        if (chunk.length < 2)
            return -1;

        frame = new Frame(chunk);
        return frame.frameLength();
    }

    ubyte[] chunk;
    Frame frame;
    T range;
}

struct Header
{
    static assert(this.sizeof == 10);
align(1):
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
}

class Frame
{
    Header* header;
    ubyte[] data;

    this(ubyte[] data)
    {
        this.data = data;
        this.header = cast(Header*) data;
    }

    this(in size_t payloadLength)
    {
        this.data = new ubyte[frameLength(payloadLength, false)];
        this.header = cast(Header*) data;
        this.length = payloadLength;
    }

    uint offset()
    {
        switch (header.len)
        {
        case 0x7E:
            return 4;
        case 0x7F:
            return 10;
        default:
            return 2;
        }
    }

    size_t frameLength()
    {
        return frameLength(header.len, header.masked);
    }

    size_t frameLength(in size_t l, bool masked)
    {
        size_t len;
        if (l < 0x7E)
        {
            len = l + 2;
        }
        else if (l <= ushort.max)
        {
            len = l + 4;
        }
        else if (l <= ulong.max)
        {
            len = l + 10;
        }
        return masked ? len + maskLength : len;
    }

    @property
    {
        size_t length()
        {
            auto l = header.len;
            switch (l)
            {
            case 0x7E:
                return bigEndianToNative!ushort(header.len16);
            case 0x7F:
                ubyte[8] loong = header.len16 ~ header.len64;
                return cast(size_t) bigEndianToNative!ulong(loong);
            default:
                return l;
            }
        }

        void length(in size_t l)
        {
            if (l < 0x7E)
            {
                header.len = cast(ubyte) l;
            }
            else if (l <= ushort.max)
            {
                header.len = 0x7E;
                header.len16 = nativeToBigEndian(cast(ushort) l);
            }
            else if (l <= ulong.max)
            {
                header.len = 0x7F;
                ubyte[8] loong = nativeToBigEndian(cast(ulong) l);
                header.len16 = loong[0 .. 2];
                header.len64 = loong[2 .. 8];
            }
        }
    }

    enum maskLength = uint.sizeof;

    void mask(ubyte[] payload, in ubyte[] m)
    {
        foreach (i, ref b; payload)
            b ^= m[i % maskLength];
    }

    @property
    {
        ubyte[] payload()
        {
            auto o = offset();
            auto l = length();
            if (header.masked)
            {
                auto d = o + maskLength;
                auto m = data[o .. d];
                auto result = data[d .. d + l];
                mask(result, m);

                return result;
            }
            else
            {
                return data[o .. o + l];
            }
        }

        void payload(in ubyte[] payload)
        {
            auto o = offset();
            if (header.masked)
            {
                import std.random;

                auto m = nativeToBigEndian(uniform(1, uint.max));

                auto d = o + maskLength;
                data[o .. d] = m;
                data[d .. $] = payload;
                mask(data[d .. $], m);
            }
            else
            {
                data[o .. $] = payload;
            }
        }
    }
}
