module unknown;

extern (C++) struct Template(T)
{
    public T var;
}

extern (C++) public extern unknown.Template!(int) global;
