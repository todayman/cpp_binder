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
std::unordered_map<string, Type*> Type::type_by_name;

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

    TypeVisitor type_visitor(printPolicy);
    type_visitor.TraverseType(qType);

    if( type_map.find(qType) == type_map.end() )
    {
        qType.dump();
        throw std::logic_error("FATAL: Traversing a clang::QualType did not place it into the type map!");
    }
    return type_map.find(qType)->second;
}

Type* Type::getByName(const string* name)
{
    decltype(type_by_name)::iterator iter = type_by_name.find(*name);
    if( iter != Type::type_by_name.end() ) {
        return iter->second;
    }
    else {
        return nullptr;
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
        case Reference:
            return getPointeeType()->isReferenceType();
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

Declaration * Type::getDeclaration() const
{
    switch (kind)
    {
        case Record:
            return getRecordDeclaration();
        case Typedef:
            return getTypedefDeclaration();
        case Enum:
            return getEnumDeclaration();
        case Union:
            return getUnionDeclaration();
        default:
            return nullptr;
    }
}

RecordDeclaration * Type::getRecordDeclaration() const
{
    assert(kind == Record);
    const clang::RecordType * cpp_record = type.getTypePtr()->getAs<clang::RecordType>();
    return dynamic_cast<RecordDeclaration*>(::getDeclaration(cpp_record->getDecl()));
}

Type * Type::getPointeeType() const
{
    assert(kind == Pointer || kind == Reference);
    if (kind == Pointer)
    {
        const clang::PointerType* ptr_type = type.getTypePtr()->castAs<clang::PointerType>();
        return Type::get(ptr_type->getPointeeType());
    }
    else if (kind == Reference)
    {
        const clang::ReferenceType* ref_type = type.getTypePtr()->castAs<clang::ReferenceType>();
        return Type::get(ref_type->getPointeeType());
    }
    else
    {
        assert(0);
    }
    return nullptr;
}

TypedefDeclaration * Type::getTypedefDeclaration() const
{
    assert(kind == Typedef);
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

EnumDeclaration * Type::getEnumDeclaration() const
{
    assert(kind == Enum);
    const clang::EnumType * clang_type = type.getTypePtr()->castAs<clang::EnumType>();
    clang::EnumDecl * clang_decl = clang_type->getDecl();

    Declaration* cpp_generic_decl = ::getDeclaration(static_cast<clang::Decl*>(clang_decl));
    return dynamic_cast<EnumDeclaration*>(cpp_generic_decl);
}

UnionDeclaration * Type::getUnionDeclaration() const
{
    assert(kind == Union);
    const clang::RecordType * clang_type = type.getTypePtr()->castAs<clang::RecordType>();
    clang::RecordDecl * clang_decl = clang_type->getDecl();

    return dynamic_cast<UnionDeclaration*>(::getDeclaration(clang_decl));
}

void Type::dump()
{
    type.dump();
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

void TypeVisitor::allocateType(const clang::QualType t, Type::Kind k)
{
    type_in_progress = new Type(t, k);
    Type::type_map.insert(std::make_pair(t, type_in_progress));
}

void TypeVisitor::allocateType(const clang::Type* t, Type::Kind k)
{
    clang::QualType qType(t, 0);
    type_in_progress = new Type(qType, k);
    Type::type_map.insert(std::make_pair(qType, type_in_progress));
}

#define WALK_UP_METHOD(KIND) \
bool TypeVisitor::WalkUpFrom##KIND##Type( clang::KIND##Type * type) \
{ \
    allocateType(type, Type::KIND); \
    return Super::WalkUpFrom##KIND##Type(type); \
}
WALK_UP_METHOD(Builtin)
WALK_UP_METHOD(Pointer)
bool TypeVisitor::WalkUpFromLValueReferenceType(clang::LValueReferenceType* type)
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
        //throw std::logic_error("Can not wrap type!");
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

// A non-instantiated class template
bool TypeVisitor::WalkUpFromInjectedClassNameType(clang::InjectedClassNameType* type)
{
    // FIXME what if the template is a union?
    // I don't translate those just yet...
    allocateType(type, Type::Record);
    return Super::WalkUpFromInjectedClassNameType(type);
}
