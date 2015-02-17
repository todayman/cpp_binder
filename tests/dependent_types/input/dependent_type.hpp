template<typename T>
struct Template
{
    T var;
    typedef T MyType;
};

Template<int>::MyType var;
