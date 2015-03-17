module unknown;

extern (C++) struct Template(T)
{
    public T var;
}

extern (C++) extern Template!(int) global;
