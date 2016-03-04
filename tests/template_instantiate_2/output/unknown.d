module unknown;

extern (C++) struct Template(int Size)
{
    public int var;
}

extern (C++) public extern unknown.Template!(4) global;
