module message;

import client;

struct Message
{
    enum Type
    {
        Text,
        Binary
    }

    Client client;
    Type type;
    ubyte[] binary;
    string text()
    {
        return cast(string) binary;
    }
}
