struct A
{
    typedef int B;
};

template<typename T>
struct Template
{
    T var;
    typedef typename T::B MyType;
};

Template<A>::MyType var;
