module unknown;

extern (C++) struct Template(int Size)
{
    public int var;
}

extern (C++) extern Template!(4) global;
