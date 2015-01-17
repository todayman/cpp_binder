module binder;

extern(C++, binder)
{
    interface string
    {
        public size_t size() const;
        public char * begin();
        public char * end();
        public char * c_str();
    }

    binder.string toBinderString(const(char)* str, size_t len);
}

auto toDString(binder.string str)
{
    import std.string : fromStringz;
    return fromStringz(str.c_str()).idup;
}

auto toBinderString(immutable(char)[] str)
{
    return binder.toBinderString(str.ptr, str.length);
}
