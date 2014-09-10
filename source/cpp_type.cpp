#include <array>
#include <iostream>
#include <string>
#include <unordered_map>

#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/Basic/SourceManager.h>

#include "cpp_type.hpp"
using namespace cpp;

std::unordered_map<const clang::Type*, std::shared_ptr<Type>> Type::type_map;
std::unordered_map<std::string, std::shared_ptr<Type>> Type::type_by_name;

void Type::printTypeNames()
{
    for( auto p : type_by_name )
    {
        std::cout << p.first << "\n";
    }
}

namespace std {
template<>
struct hash<clang::BuiltinType::Kind> : public hash<unsigned> { };
}

std::shared_ptr<Type> Type::get(clang::QualType qType, const clang::PrintingPolicy* printPolicy)
{
    // TODO could this really be NULL?
    // under what circumstances is that the case, and do I have to
    // worry about it?
    const clang::Type * cppType = qType.getTypePtr();
    decltype(type_map)::iterator iter = type_map.find(cppType);
    if( iter != Type::type_map.end() ) {
        return iter->second;
    }

    TypeVisitor type_visitor(printPolicy);
    type_visitor.TraverseType(qType);

    if( type_map.find(cppType) == type_map.end() )
        throw 5;
    return type_map.find(cppType)->second;
}

std::shared_ptr<Type> Type::getByName(const std::string& name)
{
    decltype(type_by_name)::iterator iter = type_by_name.find(name);
    if( iter != Type::type_by_name.end() ) {
        return iter->second;
    }
    else {
        return std::shared_ptr<Type>();
    }
}

TypeVisitor::TypeVisitor(const clang::PrintingPolicy* pp)
    : clang::RecursiveASTVisitor<TypeVisitor>(),
    type_to_traverse(nullptr), type_in_progress(nullptr),
    printPolicy(pp)
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
WALK_UP_METHOD(Builtin)
WALK_UP_METHOD(Pointer)
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
WALK_UP_METHOD(Array)
WALK_UP_METHOD(Function)
WALK_UP_METHOD(Typedef)
WALK_UP_METHOD(Vector)
WALK_UP_METHOD(Enum)

bool TypeVisitor::WalkUpFromRValueReferenceType(clang::RValueReferenceType* cppType)
{
    allocateType(cppType, Type::Invalid);
    throw SkipRValueRef(cppType);
}

bool TypeVisitor::WalkUpFromMemberPointerType(clang::MemberPointerType* cppType)
{
    allocateType(cppType, Type::Invalid);
    throw SkipMemberPointer(cppType);
}

bool TypeVisitor::WalkUpFromDependentNameType(clang::DependentNameType* cppType)
{
    allocateType(cppType, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromPackExpansionType(clang::PackExpansionType* cppType)
{
    allocateType(cppType, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromType(clang::Type* type)
{
    if( !type_in_progress )
        throw FatalTypeNotWrappable(type);

    if( type->isInstantiationDependentType() )
        throw SkipTemplate(type);

    return Super::WalkUpFromType(type);
}

bool TypeVisitor::VisitBuiltinType(clang::BuiltinType* cppType)
{
    assert(printPolicy != nullptr);
    std::string name = cppType->getName(*printPolicy);
    Type::type_by_name.insert(std::make_pair(name, type_in_progress));
    return true;
}

bool TypeVisitor::VisitPointerType(clang::PointerType* cppType)
{
    TypeVisitor pointeeVisitor(printPolicy);
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
        TypeVisitor field_visitor(printPolicy);
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
    TypeVisitor element_visitor(printPolicy);
    return element_visitor.TraverseType(cppType->getElementType());
}

bool TypeVisitor::VisitFunctionType(clang::FunctionType* cppType)
{
    bool continue_traversal = true;
    TypeVisitor arg_visitor(printPolicy); // Also visits return type
    continue_traversal = arg_visitor.TraverseType(cppType->getReturnType());

    // TODO get all the arguments

    return continue_traversal;
}

bool TypeVisitor::VisitLValueReferenceType(clang::LValueReferenceType* cppType)
{
    TypeVisitor target_visitor(printPolicy);
    return target_visitor.TraverseType(cppType->getPointeeType());
}

bool TypeVisitor::VisitTypedefType(clang::TypedefType* cppType)
{
    TypeVisitor real_visitor(printPolicy);
    return real_visitor.TraverseType(cppType->desugar());
}

bool TypeVisitor::WalkUpFromElaboratedType(clang::ElaboratedType* type)
{
    bool result = TraverseType(type->getNamedType());
    // TODO nullptr
    std::shared_ptr<Type> t = Type::type_map.find(type->getNamedType().getTypePtr())->second;
    Type::type_map.insert(std::make_pair(type, t));
    return result;
}

bool TypeVisitor::WalkUpFromDecayedType(clang::DecayedType* type)
{
    bool result = TraverseType(type->getDecayedType());
    // TODO nullptr
    std::shared_ptr<Type> t = Type::type_map.find(type->getDecayedType().getTypePtr())->second;
    Type::type_map.insert(std::make_pair(type, t));
    return result;
}

bool TypeVisitor::WalkUpFromParenType(clang::ParenType* type)
{
    bool result = TraverseType(type->getInnerType());
    // TODO nullptr
    std::shared_ptr<Type> t = Type::type_map.find(type->getInnerType().getTypePtr())->second;
    Type::type_map.insert(std::make_pair(type, t));
    return result;
}

bool TypeVisitor::WalkUpFromDecltypeType(clang::DecltypeType* type)
{
    bool result = TraverseType(type->getUnderlyingType());
    // TODO nullptr
    std::shared_ptr<Type> t = Type::type_map.find(type->getUnderlyingType().getTypePtr())->second;
    Type::type_map.insert(std::make_pair(type, t));
    return result;
}

bool TypeVisitor::WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromTemplateTypeParmType(clang::TemplateTypeParmType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromSubstTemplateTypeParmType(clang::SubstTemplateTypeParmType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}
