module unknown;

extern(C++) struct ArrayRef(T)
{
}

extern(C++) struct VariadicFunction(ResultT, ArgT, ResultT function(unknown.ArrayRef!(const(ArgT)*)) Func)
{
}
