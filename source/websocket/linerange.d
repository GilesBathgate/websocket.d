module linerange;

import std.traits;
import std.range;
import std.string;

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
        return !chunk.length;
    }

    string front()
    {
        return line;
    }

    void popFront() @safe
    {
        if (empty())
        {
            if (!range.empty)
            {
                range.popFront();
                chunk = cast(char[]) range.front();
            }
            else
            {
                return;
            }
        }

        auto index = chunk.indexOf('\r');
        if (index == -1)
            return;

        if (++index < chunk.length && chunk[index] == '\n')
        {
            ++index;
            line = chunk[0 .. index].idup;
            chunk = chunk[index .. $];
        }
    }

    char[] chunk;
    string line;
    T range;
}
