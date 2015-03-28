module unknown;

extern(C++) struct Template(T)
{
    public T var;
    public alias MyType = T;
}

extern(C++) extern unknown.Template!(int).MyType var;
