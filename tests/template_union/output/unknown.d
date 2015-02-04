module unknown;

extern(C++) union Template(T)
{
    public T var;
    public void* ptr;
}
