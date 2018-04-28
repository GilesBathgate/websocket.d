module frame;

enum Opcodes : ubyte
{
    Continue = 0,
    Text = 1,
    Binary = 2, // 3, 4, 5, 6, 7 Reserved
    Close = 8,
    Ping = 9,
    Pong = 10 // 11,12,13,14,15 Reserved
}

struct Frame
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
        switch (len)
        {
        case 0x7E:
            return 4;
        case 0x7F:
            return 10;
        default:
            return 2;
        }
    }

    @property
    {
        size_t length() @safe
        {
            auto l = len;
            switch (l)
            {
            case 0x7E:
                return bigEndianToNative!ushort(len16);
            case 0x7F:
                ubyte[8] loong = len16 ~ len64;
                return cast(size_t) bigEndianToNative!ulong(loong);
            default:
                return l;
            }
        }

        void length(size_t l) @safe
        {
            if (l < 0x7E)
            {
                len = cast(ubyte) l;
            }
            else if (l <= ushort.max)
            {
                len = 0x7E;
                len16 = nativeToBigEndian(cast(ushort) l);
            }
            else if (l <= ulong.max)
            {
                len = 0x7F;
                ubyte[8] loong = nativeToBigEndian(cast(ulong) l);
                len16 = loong[0 .. 2];
                len64 = loong[2 .. 8];
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

            foreach (i, ref b; data)
                b ^= mask[i % maskLength];

            return data;
        }
        else
        {
            return self[o .. o + l];
        }
    }

    ubyte[] payload(ubyte[] data)
    {
        auto self = cast(ubyte*)&this;
        auto l = data.length;
        length = l;
        auto o = offset();

        if(masked)
        {
            enum maskLength = uint.sizeof;
            auto d = o + maskLength;

            import std.random;
            auto mask = nativeToBigEndian(uniform(1, uint.max));

            ubyte[] buffer = new ubyte[o + maskLength + l];
            buffer[0 .. o] = self[0 .. o];
            buffer[o .. d] = mask;
            buffer[d .. d + l] = data;

            foreach(i, ref b; buffer[d .. d + l])
                b ^= mask[i % maskLength];

            return buffer;
        }
        else
        {
            ubyte[] buffer = new ubyte[o + l];
            buffer[0 .. o] = self[0 .. o];
            buffer[o .. o + l] = data;
            return buffer;
        }
    }
}
