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
        return !chunk.length;
    }

    Frame front()
    {
        return frame;
    }

    void popFront()
    {
        if (empty())
        {
            if (range.empty)
                return;

            range.popFront();
        }

        chunk = range.front();
        if (!chunk.length)
            return;

        frame = new Frame(chunk);
        auto length = frame.length;

        while (chunk.length < length)
        {
            range.popFront();
            chunk ~= range.front;

            Fiber.yield();
        }
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
        this.header = cast(Header*)data;
    }

    this(size_t payloadLength)
    {
        this.data = new ubyte[frameLength(payloadLength)];
        this.header = cast(Header*)data;
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

    size_t frameLength(size_t l)
    {
        if (l < 0x7E)
        {
            return l + 2;
        }
        else if (l <= ushort.max)
        {
            return l + 4;
        }
        else if (l <= ulong.max)
        {
            return l + 10;
        }
        return 0;
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

        void length(size_t l)
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

    @property
    {
        ubyte[] payload()
        {
            auto o = offset();
            auto l = length();
            if (header.masked)
            {
                enum maskLength = uint.sizeof;
                auto d = o + maskLength;
                auto mask = data[o .. d];
                auto result = data[d .. d + l];

                foreach (i, ref b; result)
                    b ^= mask[i % maskLength];

                return result;
            }
            else
            {
                return data[o .. o + l];
            }
        }

        void payload(ubyte[] payload)
        {
            auto o = offset();
            auto l = payload.length;

            if (header.masked)
            {
                enum maskLength = uint.sizeof;
                auto d = o + maskLength;

                import std.random;

                auto mask = nativeToBigEndian(uniform(1, uint.max));

                data[o .. d] = mask;
                data[d .. d + l] = payload;

                foreach (i, ref b; data[d .. d + l])
                    b ^= mask[i % maskLength];
            }
            else
            {
                data[o .. o + l] = payload;
            }
        }
    }
}
