module binder;

import std.string;
extern(C++, binder)
{
    interface string
    {
        public size_t size();
        public char * begin();
        public char * end();
        public char * c_str();
    }

    binder.string toBinderString(const(char)* str, size_t len);
}

auto toDString(binder.string str)
{
    return fromStringz(str.c_str()).idup;
    //return str.c_str()[0 .. str.size()].idup;
}

auto toBinderString(immutable(char)[] str)
{
    return binder.toBinderString(str.ptr, str.length);
    // TODO think about this copy
    /*auto buf = str.dup;
    binder.string result;
    result.buffer = buf.ptr;
    result.length = buf.length;
    return result;*/
}
