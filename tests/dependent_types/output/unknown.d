module unknown;

extern(C++) struct Template(T)
{
    public T var;
    extern(C++) alias MyType = T;
}

extern(C++) extern Template!(int).MyType var;
