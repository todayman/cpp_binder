module unknown;

extern(C++) struct Template(T)
{
    public T var;
}

Template!(int) global
