#include <array>
#include <string>
#include <unordered_map>

#include "DOutput.hpp"
#include "WrappedType.hpp"

std::unordered_map<const clang::Type*, WrappedType*> WrappedType::type_map;

class WrappedBasic : public WrappedType
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
    WrappedBasic(const clang::Type* cpp_type, Kind d)
        : WrappedType(cpp_type), d_type(d)
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

template<>
struct std::hash<clang::BuiltinType::Kind> : public std::hash<unsigned> { };

const std::array<std::string, WrappedBasic::MAX_KIND> WrappedBasic::names ({
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
static const std::unordered_map<clang::BuiltinType::Kind, WrappedBasic::Kind> cpp_to_d_builtins = {
    { clang::BuiltinType::Bool,   WrappedBasic::Bool },
    { clang::BuiltinType::UChar,  WrappedBasic::UByte },
    { clang::BuiltinType::Int,    WrappedBasic::Int },
    { clang::BuiltinType::UInt,   WrappedBasic::UInt },
    { clang::BuiltinType::Float,  WrappedBasic::Float },
    { clang::BuiltinType::Double, WrappedBasic::Double },
};

// Types in clang/AST/BuiltinTypes.def
static WrappedType * makeBuiltin(const clang::BuiltinType* cppType)
{
    WrappedBasic::Kind d_kind = cpp_to_d_builtins.at(cppType->getKind());
    return new WrappedBasic(cppType, d_kind);
}


WrappedType * WrappedType::get(const clang::Type* cppType)
{
    decltype(type_map)::iterator iter = type_map.find(cppType);
    if( iter != type_map.end() )
        return iter->second;

    WrappedType * result = nullptr;
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
