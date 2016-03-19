module unknown;

extern (C++) struct Inner(int Size) {}

extern (C++) struct Template(int Size)
{
    public unknown.Inner!(Size) var;
}

extern (C++) public extern unknown.Template!(4) global;
