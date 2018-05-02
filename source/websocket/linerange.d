module linerange;

import std.traits;
import std.range;
import std.string;
import core.thread;

LineRange!R byLine(R, S = ReturnType!((R r) => r.front))(R range)
        if (isInputRange!(Unqual!R) && isInputRange!S)
{
    return LineRange!R(range);
}

struct LineRange(T) if (is(ReturnType!((T r) => r.front) : void[]))
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

    string front()
    {
        return line;
    }

    void popFront()
    {
        auto index = getIndex();
        while (index == -1)
        {
            Fiber.yield();

            chunk ~= cast(char[]) range.front();
            if (!range.empty)
                range.popFront();

            index = getIndex();
        }

        line = cast(string) chunk[0 .. index];
        chunk = chunk[index .. $];

    }

    size_t getIndex()
    {
        auto index = chunk.indexOf('\r');
        if (index != -1 && ++index < chunk.length && chunk[index] == '\n')
            ++index;

        return index;
    }

    char[] chunk;
    string line;
    T range;
}
