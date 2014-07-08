#include <array>
#include <string>
#include <unordered_map>

#include <clang/AST/Decl.h>
#include <clang/Basic/SourceManager.h>

#include "DOutput.hpp"
#include "cpp_type.hpp"
using namespace cpp;

std::unordered_map<const clang::Type*, Type*> Type::type_map;

template<>
struct std::hash<clang::BuiltinType::Kind> : public std::hash<unsigned> { };

// Types in clang/AST/BuiltinTypes.def
static Type * makeBuiltin(const clang::BuiltinType* cppType)
{
    return new Type(cppType, Type::Builtin);
}

static Type * makePointer(const clang::PointerType* cppType)
{
    Type * result = new Type(cppType, Type::Pointer);

    // The result of getPointeeType might be NULL, but I can't
    // deal with that anyway.
    // We don't actually care about the result; we just want to
    // make sure that it exists somewhere, so ignore the result.
    (void)Type::get(cppType->getPointeeType().getTypePtr());

    return result;
}

extern clang::SourceManager * source_manager;
static void traverseClangRecord(const clang::RecordType * cppType)
{
    const clang::RecordDecl * decl = cppType->getDecl();

    // Recurse down all of the fields of the record
    if( !decl->field_empty() )
    {
        clang::RecordDecl::field_iterator end = decl->field_end();
        for( clang::RecordDecl::field_iterator iter = decl->field_begin();
                iter != end; ++iter )
        {
            // Apparently QualType::getTypePtr can be null,
            // but I don't know how to deal with it.
            const clang::Type * field_type = iter->getType().getTypePtr();
            (void)Type::get(field_type);
        }
    }
}

// Need to pass the Type * here because it's actually different
// than the RecordType *
Type * Type::makeRecord(const clang::Type* type, const clang::RecordType* cppType)
{
    Type * result = new Type(cppType, Type::Record);
    // FIXME inserting this twice,
    // but I need it here other wise I recurse infinitely when
    // structures contain a pointer to themselves
    type_map.insert(std::make_pair(type, result));

    traverseClangRecord(cppType);

    return result;
}

Type * Type::makeUnion(const clang::Type* type, const clang::RecordType* cppType)
{
    Type * result = new Type(cppType, Type::Union);
    type_map.insert(std::make_pair(type, result));

    traverseClangRecord(cppType);

    return result;
}

static Type * makeArray(const clang::ArrayType* cppType)
{
    Type * result = new Type(cppType, Type::Array);

    // TODO deal with QualType::getTypePtr being null
    (void)Type::get(cppType->getElementType().getTypePtr());
    return result;
}

static Type * makeFunction(const clang::FunctionType* cppType)
{
    Type * result = new Type(cppType, Type::Function);

    // TODO deal with QualType::getTypePtr being null
    (void)Type::get(cppType->getResultType().getTypePtr());
    // TODO get all the arguments

    return result;
}

Type * Type::get(const clang::Type* cppType)
{
    decltype(type_map)::iterator iter = type_map.find(cppType);
    if( iter != type_map.end() ) {
        return iter->second;
    }

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
    else if( cppType->isRecordType() )
    {
        // these are structs, classes, AND unions and enums?
        const clang::RecordType * recordType = cppType->getAs<clang::RecordType>();
        if( recordType->isStructureType() || recordType->isClassType() )
        {
            result = makeRecord(cppType, recordType);
        }
        else if( recordType->isUnionType() )
        {
            result = makeUnion(cppType, recordType);
        }
    }
    else if( cppType->isArrayType() )
    {
        result = makeArray(cppType->getAsArrayTypeUnsafe());
    }
    else if( cppType->isFunctionType() )
    {
        result = makeFunction(cppType->getAs<clang::FunctionType>());
    }

    if( result )
        type_map.insert(std::make_pair(cppType, result));
    else {
        throw NotWrappableException(cppType);
    }

    return result;
}
