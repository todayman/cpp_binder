#include <array>
#include <string>
#include <unordered_map>

#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/Basic/SourceManager.h>

#include "DOutput.hpp"
#include "cpp_type.hpp"
using namespace cpp;

std::unordered_map<const clang::Type*, std::shared_ptr<Type>> Type::type_map;

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

TypeVisitor::TypeVisitor()
    : clang::RecursiveASTVisitor<TypeVisitor>(),
    type_to_traverse(nullptr), type_in_progress(nullptr)
{ }

bool TypeVisitor::TraverseType(clang::QualType type)
{
    type_to_traverse = type.getTypePtrOrNull();
    if( !type_to_traverse )
        return false;
    if( Type::type_map.find(type_to_traverse) != Type::type_map.end() )
        return true;

    return Super::TraverseType(type);
}

void TypeVisitor::allocateType(const clang::Type * t, Type::Kind k)
{
    type_in_progress = std::make_shared<Type>(t, k);
    Type::type_map.insert(std::make_pair(t, type_in_progress));
}

#define WALK_UP_METHOD(KIND) \
bool TypeVisitor::WalkUpFrom##KIND##Type( clang::KIND##Type * type) \
{ \
    allocateType(type, Type::KIND); \
    return Super::WalkUpFrom##KIND##Type(type); \
}
WALK_UP_METHOD(Builtin);
WALK_UP_METHOD(Pointer);
bool TypeVisitor::WalkUpFromLValueReferenceType( clang::LValueReferenceType* type)
{
    allocateType(type, Type::Reference);
    return Super::WalkUpFromLValueReferenceType(type);
}

bool TypeVisitor::WalkUpFromRecordType(clang::RecordType* type)
{
    if( type->isStructureType() || type->isClassType() )
    {
        allocateType(type, Type::Record);
    }
    else if( type->isUnionType() )
    {
        allocateType(type, Type::Union);
    }
    return Super::WalkUpFromRecordType(type);
}
WALK_UP_METHOD(Array);
WALK_UP_METHOD(Function);
WALK_UP_METHOD(Typedef);
WALK_UP_METHOD(Vector);
WALK_UP_METHOD(Enum);

bool TypeVisitor::WalkUpFromRValueReferenceType(clang::RValueReferenceType* cppType)
{
    throw SkipRValueRef(cppType);
}

bool TypeVisitor::WalkUpFromMemberPointerType(clang::MemberPointerType* cppType)
{
    throw SkipMemberPointer(cppType);
}

bool TypeVisitor::WalkUpFromType(clang::Type* type)
{
    if( !type_in_progress )
        throw NotWrappableException(type);

    if( type->isInstantiationDependentType() )
        throw SkipTemplate(type);

    return Super::WalkUpFromType(type);
}

bool TypeVisitor::VisitPointerType(clang::PointerType* cppType)
{
    TypeVisitor pointeeVisitor;
    return pointeeVisitor.TraverseType(cppType->getPointeeType());
}

bool TypeVisitor::VisitRecordType(clang::RecordType* cppType)
{
    bool continue_traversal = true;
    const clang::RecordDecl * decl = cppType->getDecl();
    // Recurse down all of the fields of the record
    if( !decl->field_empty() )
    {
        clang::RecordDecl::field_iterator end = decl->field_end();
        TypeVisitor field_visitor;
        for( clang::RecordDecl::field_iterator iter = decl->field_begin();
                iter != end && continue_traversal; ++iter )
        {
            field_visitor.reset();
            continue_traversal = field_visitor.TraverseType(iter->getType());
        }
    }

    return continue_traversal;
}

bool TypeVisitor::VisitArrayType(clang::ArrayType* cppType)
{
    TypeVisitor element_visitor;
    return element_visitor.TraverseType(cppType->getElementType());
}

bool TypeVisitor::VisitFunctionType(clang::FunctionType* cppType)
{
    bool continue_traversal = true;
    TypeVisitor arg_visitor; // Also visits return type
    continue_traversal = arg_visitor.TraverseType(cppType->getResultType());

    // TODO get all the arguments

    return continue_traversal;
}

bool TypeVisitor::VisitLValueReferenceType(clang::LValueReferenceType* cppType)
{
    TypeVisitor target_visitor;
    return target_visitor.TraverseType(cppType->getPointeeType());
}

bool TypeVisitor::VisitTypedefType(clang::TypedefType* cppType)
{
    TypeVisitor real_visitor;
    return real_visitor.TraverseType(cppType->desugar());
}

bool TypeVisitor::WalkUpFromElaboratedType(clang::ElaboratedType* type)
{
    return TraverseType(type->getNamedType());
}

bool TypeVisitor::WalkUpFromDecayedType(clang::DecayedType* type)
{
    return TraverseType(type->getDecayedType());
}

bool TypeVisitor::WalkUpFromParenType(clang::ParenType* type)
{
    return TraverseType(type->getInnerType());
}

bool TypeVisitor::WalkUpFromDecltypeType(clang::DecltypeType* type)
{
    return TraverseType(type->getUnderlyingType());
}

bool TypeVisitor::WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type)
{
    throw SkipTemplate(type);
}

bool TypeVisitor::WalkUpFromTemplateTypeParmType(clang::TemplateTypeParmType* type)
{
    throw SkipTemplate(type);
}

bool TypeVisitor::WalkUpFromSubstTemplateTypeParmType(clang::SubstTemplateTypeParmType* type)
{
    throw SkipTemplate(type);
}
