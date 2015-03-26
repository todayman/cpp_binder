module unknown;

extern(C++) struct Template(T)
{
    public T var;
    alias MyType = T;
}

extern(C++) extern unknown.Template!(int).MyType var;
