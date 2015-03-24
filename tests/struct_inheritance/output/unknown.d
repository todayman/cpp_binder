module unknown;

extern(C++) struct Base
{
    public int a;
}

extern(C++) struct Simple
{
    unknown.Base _superclass;
    alias _superclass this;

    public char b;
    public float c;

}

