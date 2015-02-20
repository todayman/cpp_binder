module unknown;

extern (C++) struct Template(int Size)
{
    public int var;
}

extern (C++) extern unknown.Template!(4) global;
