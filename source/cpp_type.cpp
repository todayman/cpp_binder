#include <array>
#include <string>
#include <unordered_map>

#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/Basic/SourceManager.h>

#include "DOutput.hpp"
#include "cpp_type.hpp"
using namespace cpp;

std::unordered_map<const clang::Type*, Type*> Type::type_map;

template<>
struct std::hash<clang::BuiltinType::Kind> : public std::hash<unsigned> { };

bool hasTemplateParent(const clang::CXXRecordDecl * parent_record)
{
    while(!parent_record->isTemplateDecl() && !parent_record->getDescribedClassTemplate())
    {
        const clang::DeclContext * parent_context = parent_record->getParent();
        if( parent_context->isRecord() )
        {
            const clang::TagDecl * parent_decl = clang::TagDecl::castFromDeclContext(parent_context);
            if( parent_decl->getKind() == clang::Decl::CXXRecord )
            {
                parent_record = static_cast<const clang::CXXRecordDecl*>(parent_decl);
            }
            else
            {
                return false;
            }
        }
        else {
            return false;
        }
    }
    return true;
}

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

static Type * makeReference(const clang::ReferenceType* cppType)
{
    Type * result = new Type(cppType, Type::Reference);

    // TODO deal with QualType::getTypePtr being null
    (void)Type::get(cppType->getPointeeType().getTypePtr());

    return result;
}

static Type * makeTypedef(const clang::TypedefType* cppType)
{
    Type * result = new Type(cppType, Type::Typedef);

    // TODO deal with QualType::getTypePtr being null
    (void)Type::get(cppType->desugar().getTypePtr());

    return result;
}

static Type * makeVector(const clang::VectorType* cppType)
{
    return new Type(cppType, Type::Vector);
}

static Type * makeEnum(const clang::EnumType* cppType)
{
    return new Type(cppType, Type::Enum);
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
    else if( cppType->isReferenceType() )
    {
        if( cppType->isLValueReferenceType() )
        {
            result = makeReference(cppType->getAs<clang::ReferenceType>());
        }
        else if( cppType->isRValueReferenceType() )
        {
            throw SkipRValueRef(cppType->getAs<clang::RValueReferenceType>());
        }
    }
    else if( cppType->getAs<clang::TypedefType>() )
    {
        const clang::TypedefType * type = cppType->getAs<clang::TypedefType>();
        result = makeTypedef(type);
    }
    else if( cppType->isVectorType() )
    {
        result = makeVector(cppType->getAs<clang::VectorType>());
    }
    else if( cppType->isEnumeralType() )
    {
        result = makeEnum(cppType->getAs<clang::EnumType>());
    }
    else if( cppType->isInstantiationDependentType() )
    {
        throw SkipTemplate(cppType);
    }
    else if( cppType->isMemberPointerType() )
    {
        throw SkipMemberPointer(cppType->getAs<clang::MemberPointerType>());
    }
    else {
        std::cout << "type class: " << cppType->getTypeClass() << "\n";
        std::cout << "type class name: " << cppType->getTypeClassName() << "\n";
#define PRINT(x) std::cout << #x << ": " << clang::Type::x << "\n"
        std::cout << "attributed type: " << cppType->getAs<clang::AttributedType>() << "\n";
        std::cout << "dependent: " << cppType->isDependentType() << "\n";
        std::cout << "attributed: " << cppType->getAs<clang::AttributedType>() << "\n";
        std::cout << "integer: " << cppType->isFundamentalType() << "\n";
        std::cout << "atomic: " << cppType->isAtomicType() << "\n";
        std::cout << "array: " << cppType->isArrayType() << "\n";
        std::cout << "specifer: " << cppType->isSpecifierType() << "\n";
        std::cout << "elaborated specifer: " << cppType->isElaboratedTypeSpecifier() << "\n";
        std::cout << "constant size: " << cppType->isConstantSizeType() << "\n";
        std::cout << "vector: " << cppType->isVectorType() << "\n";
        std::cout << "ext vector: " << cppType->isExtVectorType() << "\n";
        std::cout << "placeholder: " << cppType->isPlaceholderType() << "\n";
        std::cout << "object: " << cppType->isObjectType() << "\n";
        std::cout << "enumeral: " << cppType->isEnumeralType() << "\n";
        cppType->dump();
    }

    if( result )
        type_map.insert(std::make_pair(cppType, result));
    else {
        throw NotWrappableException(cppType);
    }

    return result;
}
