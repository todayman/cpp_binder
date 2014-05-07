#include "WrappedType.hpp"

std::unordered_map<const clang::Type*, WrappedType*> WrappedType::type_map;

WrappedType * WrappedType::get(const clang::Type* cppType)
{
    return nullptr;
}
