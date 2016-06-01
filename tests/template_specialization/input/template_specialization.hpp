template<typename T>
class Template
{
public:
    virtual void func();
};

template <>
class Template<int>
{
public:
    virtual int func();
};
