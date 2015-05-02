template<int Size>
struct Inner
{
};

template<int Size>
struct Template
{
    Inner<Size> var;
};

Template<4> global;
