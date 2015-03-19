module unknown;

extern (C++) struct Template(T)
{
    public T var;
}

extern (C++) extern unknown.Template!(int) global;
