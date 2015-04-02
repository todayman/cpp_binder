struct A
{
    typedef int B;
    typedef char C;
};

template<typename T>
struct Template
{
    T var;
    typedef typename T::B MyType;
    typedef typename T::C& OtherType;

    OtherType method();
};

Template<A>::MyType var;
