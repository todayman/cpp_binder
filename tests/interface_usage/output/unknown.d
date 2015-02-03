module unknown;

extern(C++) interface Interface
{
    public void aFunc();
}

extern(C++) extern unknown.Interface global;
