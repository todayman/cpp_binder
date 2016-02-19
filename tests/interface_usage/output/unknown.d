module unknown;

extern(C++) interface Interface
{
    public void aFunc();
}

extern(C++) public extern unknown.Interface global;
