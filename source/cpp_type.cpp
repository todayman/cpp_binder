/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014 Paul O'Neil <redballoon36@gmail.com>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <array>
#include <iostream>
#include <string>
#include <unordered_map>

#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/TypeOrdering.h>
#include <clang/Basic/SourceManager.h>

#include "cpp_type.hpp"
#include "cpp_decl.hpp"
//using namespace cpp;

std::unordered_map<const clang::QualType, Type*> Type::type_map;
std::unordered_multimap<string, Type*> Type::type_by_name;

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

std::size_t std::hash<const clang::QualType>::operator()(const clang::QualType qType) const
{
    return llvm::DenseMapInfo<clang::QualType>::getHashValue(qType);
}

Type* Type::get(const clang::QualType& qType, const clang::PrintingPolicy* printPolicy)
{
    decltype(type_map)::iterator iter = type_map.find(qType);
    if( iter != Type::type_map.end() ) {
        return iter->second;
    }

    // TODO understand why this happens
    if (qType.getTypePtrOrNull() == nullptr)
    {
        std::cerr << "WARNING: Attempted to look up a QualType that has a null Type pointer\n";
        return nullptr;
    }

    TypeVisitor type_visitor(printPolicy);
    type_visitor.TraverseType(qType);

    if( type_map.find(qType) == type_map.end() )
    {
        qType.dump();
        throw std::logic_error("FATAL: Traversing a clang::QualType did not place it into the type map!");
    }
    return type_map.find(qType)->second;
}

Type::range_t Type::getByName(const string* name)
{
    range_t search = type_by_name.equal_range(*name);
    if( search.first != Type::type_by_name.end() ) {
        return search;
    }
    else {
        return range_t();
    }
}

Type::Kind Type::getKind() const
{
    return kind;
}

Strategy Type::getStrategy() const
{
    return strategy;
}

bool Type::isReferenceType() const
{
    switch (strategy)
    {
        case INTERFACE:
        case CLASS:
        case OPAQUE_CLASS:
            return true;
        case STRUCT:
            return false;
        case UNKNOWN:
        case REPLACE:
            // deliberately falling out
            ;
    };

    switch (kind)
    {
        case Qualified:
            return unqualifiedType()->isReferenceType();
        default:
            return false;
            // TODO this may not be all cases
    }
}

string* Type::getReplacement() const
{
    if( strategy != REPLACE )
    {
        throw WrongStrategy();
    }
    string * result = new string(target_name);
    return result;
}
string* Type::getReplacementModule() const
{
    if( strategy != REPLACE )
    {
        throw WrongStrategy();
    }
    string * result = new string(target_module);
    return result;
}

void Type::setReplacementModule(string new_mod)
{
    target_module = new_mod;
}

Type * Type::unqualifiedType()
{
    if (type.getQualifiers().empty())
    {
        return this;
    }
    else
    {
        clang::QualType unqual = type;
        unqual.removeLocalConst();
        return Type::get(unqual);
    }
}
const Type * Type::unqualifiedType() const
{
    if (type.getQualifiers().empty())
    {
        return this;
    }
    else
    {
        clang::QualType unqual = type;
        unqual.removeLocalConst();
        return Type::get(unqual);
    }
}

bool Type::isConst() const
{
    return type.isLocalConstQualified();
}

Declaration* RecordType::getDeclaration() const
{
    return getRecordDeclaration();
}

RecordDeclaration * RecordType::getRecordDeclaration() const
{
    assert(kind == Record || kind == TemplateSpecialization);

    if (kind == TemplateSpecialization)
    {
        Declaration * decl = getTemplateDeclaration();
        return dynamic_cast<RecordTemplateDeclaration*>(decl);
    }

    const clang::RecordType * cpp_record = type.getTypePtr()->getAs<clang::RecordType>();
    if (cpp_record != nullptr)
    {
        return dynamic_cast<RecordDeclaration*>(::getDeclaration(cpp_record->getDecl()));
    }

    const clang::InjectedClassNameType * classname_type = type.getTypePtr()->getAs<clang::InjectedClassNameType>();
    if (classname_type != nullptr)
    {
        Declaration* decl = ::getDeclaration(classname_type->getDecl());
        // TODO the declaration of an injected classname type is the
        // CXXRecordDecl inside of the ClassTemplateDecl
        // Make sure this is behaving the way I expect
        auto result = dynamic_cast<RecordDeclaration*>(decl);
        return result;
    }

    return nullptr;
}

Type * PointerType::getPointeeType() const
{
    const clang::PointerType* ptr_type = type.getTypePtr()->castAs<clang::PointerType>();
    return Type::get(ptr_type->getPointeeType());
}

Type * ReferenceType::getPointeeType() const
{
    const clang::ReferenceType* ref_type = type.getTypePtr()->castAs<clang::ReferenceType>();
    return Type::get(ref_type->getPointeeType());
}
bool ReferenceType::isReferenceType() const
{
    // TODO think about this again and add a comment
    return getPointeeType()->isReferenceType();
}

bool TypedefType::isReferenceType() const
{
    return get(reinterpret_cast<const clang::TypedefType*>(type.getTypePtr())->desugar())->isReferenceType();
}

Declaration* TypedefType::getDeclaration() const
{
    return getTypedefDeclaration();
}

TypedefDeclaration * TypedefType::getTypedefDeclaration() const
{
    const clang::TypedefType * clang_type = type.getTypePtr()->getAs<clang::TypedefType>();
    clang::TypedefNameDecl * clang_decl = clang_type->getDecl();

    Declaration* this_declaration = ::getDeclaration(static_cast<clang::Decl*>(clang_decl));
    if( !this_declaration )
    {
        clang_decl->dump();
        throw std::runtime_error("Found a declaration that I'm not wrapping.");
    }

    return dynamic_cast<TypedefDeclaration*>(this_declaration);
}

Declaration* EnumType::getDeclaration() const
{
    return getEnumDeclaration();
}

EnumDeclaration * EnumType::getEnumDeclaration() const
{
    const clang::EnumType * clang_type = type.getTypePtr()->castAs<clang::EnumType>();
    clang::EnumDecl * clang_decl = clang_type->getDecl();

    Declaration* cpp_generic_decl = ::getDeclaration(static_cast<clang::Decl*>(clang_decl));
    return dynamic_cast<EnumDeclaration*>(cpp_generic_decl);
}

Declaration* UnionType::getDeclaration() const
{
    return getUnionDeclaration();
}
UnionDeclaration * UnionType::getUnionDeclaration() const
{
    const clang::RecordType * clang_type = type.getTypePtr()->castAs<clang::RecordType>();
    clang::RecordDecl * clang_decl = clang_type->getDecl();

    return dynamic_cast<UnionDeclaration*>(::getDeclaration(clang_decl));
}

TemplateTypeArgumentDeclaration * Type::getTemplateTypeArgumentDeclaration() const
{
    assert(kind == TemplateArgument);
    assert(template_list != nullptr);

    const clang::TemplateTypeParmType * clang_type = type.getTypePtr()->castAs<clang::TemplateTypeParmType>();
    clang::NamedDecl* clang_decl = template_list->getParam(clang_type->getIndex());
    assert(isTemplateTypeParmDecl(clang_decl));
    return dynamic_cast<TemplateTypeArgumentDeclaration*>(::getDeclaration(clang_decl));
}

Declaration* Type::getTemplateDeclaration() const
{
    assert(kind == TemplateSpecialization);

    const clang::TemplateSpecializationType* clang_type = reinterpret_cast<const clang::TemplateSpecializationType*>(type.getTypePtr());
    clang::TemplateDecl* clang_decl = clang_type->getTemplateName().getAsTemplateDecl();
    return ::getDeclaration(clang_decl);
}

unsigned Type::getTemplateArgumentCount() const
{
    assert(kind == TemplateSpecialization);

    const clang::TemplateSpecializationType* clang_type = reinterpret_cast<const clang::TemplateSpecializationType*>(type.getTypePtr());
    return clang_type->getNumArgs();
}

TemplateArgumentInstanceIterator* Type::getTemplateArgumentBegin()
{
    assert(kind == TemplateSpecialization);

    const clang::TemplateSpecializationType* clang_type = reinterpret_cast<const clang::TemplateSpecializationType*>(type.getTypePtr());
    return new TemplateArgumentInstanceIterator(clang_type->begin());
}

TemplateArgumentInstanceIterator* Type::getTemplateArgumentEnd()
{
    assert(kind == TemplateSpecialization);

    const clang::TemplateSpecializationType* clang_type = reinterpret_cast<const clang::TemplateSpecializationType*>(type.getTypePtr());
    return new TemplateArgumentInstanceIterator(clang_type->end());
}

void Type::dump()
{
    type.dump();
}

Type* TemplateArgumentInstanceIterator::operator*()
{
    assert(cpp_iter->getKind() == clang::TemplateArgument::Type);

    return Type::get(cpp_iter->getAsType());
}

TypeVisitor::TypeVisitor(const clang::PrintingPolicy* pp)
    : clang::RecursiveASTVisitor<TypeVisitor>(),
    type_to_traverse(nullptr), type_in_progress(nullptr),
    printPolicy(pp)
{ }

bool TypeVisitor::TraverseType(clang::QualType type)
{
    if( Type::type_map.find(type) != Type::type_map.end() )
        return true;

    bool result;
    if (type.isLocalConstQualified())
    {
        allocateType(type, Type::Qualified);

        clang::QualType unqual = type;
        // Qualifiers handled here also should to be handled in
        // Type::unqualifiedType()
        unqual.removeLocalConst();
        result = TraverseType(unqual);

        return result;
    }
    else if (!type.getQualifiers().empty())
    {
        std::cerr << "ERROR: Unrecognized qualifiers (\"" << type.getQualifiers().getAsString() << "\") for type ";
        type.dump();
        allocateType(type, Type::Invalid);
        result = true;
    }
    else
    {
        result = Super::TraverseType(type);
    }

    return result;
}

template<typename T>
void TypeVisitor::allocateType(const clang::QualType t, Type::Kind k)
{
    type_in_progress = new T(t, k);
    Type::type_map.insert(std::make_pair(t, type_in_progress));
}

template<typename T>
void TypeVisitor::allocateType(const clang::Type* t, Type::Kind k)
{
    clang::QualType qType(t, 0);
    type_in_progress = new T(qType, k);
    Type::type_map.insert(std::make_pair(qType, type_in_progress));
}

#define WALK_UP_METHOD(KIND) \
bool TypeVisitor::WalkUpFrom##KIND##Type( clang::KIND##Type * type) \
{ \
    allocateType(type, Type::KIND); \
    return Super::WalkUpFrom##KIND##Type(type); \
}
WALK_UP_METHOD(Builtin)
bool TypeVisitor::WalkUpFromPointerType(clang::PointerType* type)
{
    allocateType<PointerType>(type, Type::Pointer);
    return Super::WalkUpFromPointerType(type);
}
bool TypeVisitor::WalkUpFromLValueReferenceType(clang::LValueReferenceType* type)
{
    allocateType<ReferenceType>(type, Type::Reference);
    return Super::WalkUpFromLValueReferenceType(type);
}

bool TypeVisitor::WalkUpFromRecordType(clang::RecordType* type)
{
    if( type->isStructureType() || type->isClassType() )
    {
        allocateType<RecordType>(type, Type::Record);
    }
    else if( type->isUnionType() )
    {
        allocateType<UnionType>(type, Type::Union);
    }
    return Super::WalkUpFromRecordType(type);
}
WALK_UP_METHOD(Array)
WALK_UP_METHOD(Function)
bool TypeVisitor::WalkUpFromTypedefType(clang::TypedefType* type)
{
    allocateType<TypedefType>(type, Type::Typedef);
    return Super::WalkUpFromTypedefType(type);
}
    
WALK_UP_METHOD(Vector)
bool TypeVisitor::WalkUpFromEnumType(clang::EnumType* type)
{
    allocateType<EnumType>(type, Type::Enum);
    return Super::WalkUpFromEnumType(type);
}

bool TypeVisitor::WalkUpFromRValueReferenceType(clang::RValueReferenceType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromType(clang::Type* type)
{
    if( !type_in_progress )
    {
        allocateType(type, Type::Invalid);
        type->dump();
        throw std::logic_error("Can not wrap type!");
        return false;
    }

    return Super::WalkUpFromType(type);
}

bool TypeVisitor::VisitBuiltinType(clang::BuiltinType* cppType)
{
    assert(printPolicy != nullptr);
    string name = cppType->getName(*printPolicy).data();
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

    // To avoid mutually recursion in DeclVisitor
    // TODO with other types like union, etc.
    clang::RecordDecl * decl = cppType->getDecl();
    DeclVisitor declVisitor(printPolicy);
    declVisitor.TraverseDecl(decl);

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
    Type* t = Type::type_map.find(type->getNamedType())->second;
    // FIXME does this really need to go into the map here?  Does that happen during TraverseType?
    Type::type_map.insert(std::make_pair(type->getNamedType(), t));
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), t));
    return result;
}

bool TypeVisitor::WalkUpFromDecayedType(clang::DecayedType* type)
{
    bool result = TraverseType(type->getDecayedType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getDecayedType())->second;
    // FIXME does this really need to go into the map here?  Does that happen during TraverseType?
    Type::type_map.insert(std::make_pair(type->getDecayedType(), t));
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), t));
    return result;
}

bool TypeVisitor::WalkUpFromParenType(clang::ParenType* type)
{
    bool result = TraverseType(type->getInnerType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getInnerType())->second;
    // FIXME does this really need to go into the map here?
    Type::type_map.insert(std::make_pair(type->getInnerType(), t));
    return result;
}

bool TypeVisitor::WalkUpFromDecltypeType(clang::DecltypeType* type)
{
    bool result = TraverseType(type->getUnderlyingType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getUnderlyingType())->second;
    // FIXME does this really need to go into the map here?
    Type::type_map.insert(std::make_pair(type->getUnderlyingType(), t));
    // TODO is resolving the decltype the best thing to do here?
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), t));
    return result;
}

bool TypeVisitor::WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type)
{
    allocateType(type, Type::TemplateSpecialization);
    std::string name = type->getTemplateName().getAsTemplateDecl()->getQualifiedNameAsString();
    // TODO Make sure I'm not making too many of these!
    string binder_name(name.c_str(), name.size());
    Type::type_by_name.insert(std::make_pair(binder_name, type_in_progress));
    return true;
}

bool TypeVisitor::WalkUpFromTemplateTypeParmType(clang::TemplateTypeParmType* type)
{
    allocateType(type, Type::TemplateArgument);
    return Super::WalkUpFromTemplateTypeParmType(type);
}

bool TypeVisitor::WalkUpFromSubstTemplateTypeParmType(clang::SubstTemplateTypeParmType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

// A non-instantiated class template
bool TypeVisitor::WalkUpFromInjectedClassNameType(clang::InjectedClassNameType* type)
{
    // FIXME what if the template is a union?
    // I don't translate those just yet...
    allocateType(type, Type::Record);
    return Super::WalkUpFromInjectedClassNameType(type);
}

bool TypeVisitor::WalkUpFromDependentNameType(clang::DependentNameType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromTypeOfExprType(clang::TypeOfExprType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromUnaryTransformType(clang::UnaryTransformType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromDependentTemplateSpecializationType(clang::DependentTemplateSpecializationType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromMemberPointerType(clang::MemberPointerType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}

bool TypeVisitor::WalkUpFromPackExpansionType(clang::PackExpansionType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}


bool TypeVisitor::WalkUpFromAutoType(clang::AutoType* type)
{
    allocateType(type, Type::Invalid);
    return false;
}
