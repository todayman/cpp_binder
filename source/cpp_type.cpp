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
#include <clang/Basic/SourceManager.h>

#include "cpp_type.hpp"
#include "cpp_decl.hpp"
//using namespace cpp;

std::unordered_map<const clang::Type*, Type*> Type::type_map;
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

Type* Type::get(const clang::QualType& qType, const clang::PrintingPolicy* printPolicy)
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

Type::Kind Type::getKind()
{
    return kind;
}
Type::Kind Type::getKind() const
{
    return kind;
}

Strategy Type::getStrategy()
{
    return strategy;
}
Strategy Type::getStrategy() const
{
    return strategy;
}

string* Type::getReplacement()
{
    if( strategy != REPLACE )
    {
        throw WrongStrategy();
    }
    string * result = new string(target_name);
    return result;
}

const string* Type::getReplacement() const
{
    if( strategy != REPLACE )
    {
        throw WrongStrategy();
    }
    return new string(target_name);
}

RecordDeclaration * Type::getRecordDeclaration()
{
    assert(kind == Record);
    const clang::RecordType * cpp_record = cpp_type->getAs<clang::RecordType>();
    return dynamic_cast<RecordDeclaration*>(getDeclaration(cpp_record->getDecl()));
}

Type * Type::getPointeeType()
{
    assert(kind == Pointer || kind == Reference);
    if (kind == Pointer)
    {
        const clang::PointerType* ptr_type = cpp_type->castAs<clang::PointerType>();
        return Type::get(ptr_type->getPointeeType());
    }
    else if (kind == Reference)
    {
        const clang::ReferenceType* ref_type = cpp_type->castAs<clang::ReferenceType>();
        return Type::get(ref_type->getPointeeType());
    }
    else
    {
        assert(0);
    }
    return nullptr;
}

TypedefDeclaration * Type::getTypedefDeclaration()
{
    assert(kind == Typedef);
    const clang::TypedefType * clang_type = cpp_type->getAs<clang::TypedefType>();
    clang::TypedefNameDecl * clang_decl = clang_type->getDecl();

    Declaration* this_declaration = getDeclaration(static_cast<clang::Decl*>(clang_decl));
    if( !this_declaration )
    {
        clang_decl->dump();
        throw std::runtime_error("Found a declaration that I'm not wrapping.");
    }

    return dynamic_cast<TypedefDeclaration*>(this_declaration);
}

EnumDeclaration * Type::getEnumDeclaration()
{
    assert(kind == Enum);
    const clang::EnumType * clang_type = cpp_type->castAs<clang::EnumType>();
    clang::EnumDecl * clang_decl = clang_type->getDecl();

    Declaration* cpp_generic_decl = getDeclaration(static_cast<clang::Decl*>(clang_decl));
    return dynamic_cast<EnumDeclaration*>(cpp_generic_decl);
}

UnionDeclaration * Type::getUnionDeclaration()
{
    assert(kind == Union);
    const clang::RecordType * clang_type = cpp_type->castAs<clang::RecordType>();
    clang::RecordDecl * clang_decl = clang_type->getDecl();

    return dynamic_cast<UnionDeclaration*>(getDeclaration(clang_decl));
}

void Type::dump()
{
    cpp_type->dump();
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
    type_in_progress = new Type(t, k);
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
    Type* t = Type::type_map.find(type->getNamedType().getTypePtr())->second;
    Type::type_map.insert(std::make_pair(type, t));
    return result;
}

bool TypeVisitor::WalkUpFromDecayedType(clang::DecayedType* type)
{
    bool result = TraverseType(type->getDecayedType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getDecayedType().getTypePtr())->second;
    Type::type_map.insert(std::make_pair(type, t));
    return result;
}

bool TypeVisitor::WalkUpFromParenType(clang::ParenType* type)
{
    bool result = TraverseType(type->getInnerType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getInnerType().getTypePtr())->second;
    Type::type_map.insert(std::make_pair(type, t));
    return result;
}

bool TypeVisitor::WalkUpFromDecltypeType(clang::DecltypeType* type)
{
    bool result = TraverseType(type->getUnderlyingType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getUnderlyingType().getTypePtr())->second;
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
