#include <array>
#include <string>
#include <unordered_map>

#include "DOutput.hpp"
#include "cpp_type.hpp"
using namespace cpp;

std::unordered_map<const clang::Type*, Type*> Type::type_map;

namespace cpp {
    class Builtin : public Type
    {
        public:
        Builtin(const clang::Type* cpp_type)
            : Type(cpp_type)
        { }
    };

    class Pointer : public Type
    {
        public:
        Pointer(const clang::Type* cpp_type)
            : Type(cpp_type)
        { }

        // For now, query the cpp_type to get the pointer target
        // then look that up in the map.
    };
}

template<>
struct std::hash<clang::BuiltinType::Kind> : public std::hash<unsigned> { };

// Types in clang/AST/BuiltinTypes.def
static Type * makeBuiltin(const clang::BuiltinType* cppType)
{
    return new Builtin(cppType);
}

static Type * makePointer(const clang::PointerType* cppType)
{
    Type * result = new Pointer(cppType);

    // The result of getPointeeType might be NULL, but I can't
    // deal with that anyway.
    // We don't actually care about the result; we just want to
    // make sure that it exists somewhere, so ignore the result.
    (void)Type::get(cppType->getPointeeType().getTypePtr());

    return result;
}

Type * Type::get(const clang::Type* cppType)
{
    decltype(type_map)::iterator iter = type_map.find(cppType);
    if( iter != type_map.end() )
        return iter->second;

    Type * result = nullptr;
    // Builtin type ignores typdefs and qualifiers
    if( cppType->isBuiltinType() )
    {
        result = makeBuiltin(cppType->getAs<clang::BuiltinType>());
    }
    else if( cppType->isPointerType() )
    {
        result = makePointer(cppType->getAs<clang::PointerType>());
    }

    if( result )
        type_map.insert(std::make_pair(cppType, result));
    else
        throw std::runtime_error("No way to wrap type"); // TODO put type into exception

    return result;
}
