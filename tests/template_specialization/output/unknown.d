module unknown;

extern(C++) interface Template(T)
{
    public void func();
}

extern(C++) interface Template(T : int)
{
    public int func();
}
