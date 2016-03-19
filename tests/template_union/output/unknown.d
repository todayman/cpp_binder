module unknown;

extern(C++) public union Template(T)
{
    public T var;
    public void* ptr;
}
