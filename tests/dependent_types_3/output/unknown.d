module unknown;

extern(C++) struct A
{
    public alias B = int;
}

extern(C++) struct Template(T)
{
    public T var;
    public alias MyType = T.B;

    public ref T.C method();
}

extern(C++) extern unknown.Template!(unknown.A).MyType var;
