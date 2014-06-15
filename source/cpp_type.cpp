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
        enum Kind {
            Bool,
            Byte,
            UByte,
            Int,
            UInt,
            Float,
            Double,
        };
        static constexpr size_t MAX_KIND = Double + 1;
        private:
        Kind d_type;
    
        static const std::array<std::string, MAX_KIND> names;
    
        public:
        Builtin(const clang::Type* cpp_type, Kind d)
            : Type(cpp_type), d_type(d)
        { }
    
        virtual bool isTranslationFinal() override
        {
            return true;
        }
    
        virtual void translate(DOutput& output) const
        {
            output.putItem(names.at(d_type));
        }
    };
}

template<>
struct std::hash<clang::BuiltinType::Kind> : public std::hash<unsigned> { };

const std::array<std::string, Builtin::MAX_KIND> Builtin::names ({
    "bool",
    "byte",
    "ubyte",
    "int",
    "uint",
    "float",
    "double",
});

// TODO move this out to configuration
// C++ types in clang/AST/BuiltinTypes.def
static const std::unordered_map<clang::BuiltinType::Kind, Builtin::Kind> cpp_to_d_builtins = {
    { clang::BuiltinType::Bool,   Builtin::Bool },
    { clang::BuiltinType::UChar,  Builtin::UByte },
    { clang::BuiltinType::Int,    Builtin::Int },
    { clang::BuiltinType::UInt,   Builtin::UInt },
    { clang::BuiltinType::Float,  Builtin::Float },
    { clang::BuiltinType::Double, Builtin::Double },
};

// Types in clang/AST/BuiltinTypes.def
static Type * makeBuiltin(const clang::BuiltinType* cppType)
{
    Builtin::Kind d_kind = cpp_to_d_builtins.at(cppType->getKind());
    return new Builtin(cppType, d_kind);
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

    if( result )
        type_map.insert(std::make_pair(cppType, result));
    else
        throw std::runtime_error("No way to wrap type"); // TODO put type into exception

    return result;
}
