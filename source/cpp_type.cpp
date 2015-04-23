/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014-2015 Paul O'Neil <redballoon36@gmail.com>
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
#include <sstream>
#include <string>
#include <unordered_map>

#include <clang/AST/Decl.h>
#include <clang/AST/DeclCXX.h>
#include <clang/AST/TypeOrdering.h>
#include <clang/Basic/SourceManager.h>

#include "cpp_type.hpp"
#include "cpp_decl.hpp"
#include "cpp_expr.hpp"
#include "nested_name_resolver.hpp"
//using namespace cpp;

std::unordered_map<const clang::QualType, Type*> Type::type_map;
std::unordered_multimap<string, Type*> Type::type_by_name;

TypeAttributes* TypeAttributes::make()
{
    return new TypeAttributes();
}

Strategy TypeAttributes::getStrategy() const
{
    return strategy;
}

void TypeAttributes::setStrategy(Strategy s)
{
    strategy = s;
}

void TypeAttributes::setTargetName(string* new_target)
{
    target_name = *new_target;
}

void TypeAttributes::setTargetModule(string* new_module)
{
    target_module = *new_module;
}

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

Type* Type::get(const clang::Type* type, const clang::PrintingPolicy* printPolicy)
{
    return Type::get(clang::QualType(type, 0), printPolicy);
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
        //std::cerr << "WARNING: Attempted to look up a QualType that has a null Type pointer\n";
        return nullptr;
    }

    ClangTypeVisitor type_visitor(printPolicy);
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

void Type::applyAttributes(const TypeAttributes* attribs)
{
    if (attribs->strategy == REPLACE)
    {
        chooseReplaceStrategy(&attribs->target_name);
    }
    else if (attribs->strategy != UNKNOWN)
    {
        setStrategy(attribs->strategy);
    }

    setReplacementModule(attribs->target_module);
}

bool BuiltinType::hasDeclaration() const
{
    return false;
}

bool BuiltinType::isWrappable(bool)
{
    return type->getKind() != clang::BuiltinType::Dependent
        && target_name.size() > 0;
}

Type * QualifiedType::unqualifiedType()
{
    if (type.getLocalQualifiers().empty())
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
const Type * QualifiedType::unqualifiedType() const
{
    if (type.getLocalQualifiers().empty())
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

bool InvalidType::hasDeclaration() const
{
    // TODO this is not always false, but this is the conservative choice
    return false;
}

bool QualifiedType::isConst() const
{
    return type.isLocalConstQualified();
}

bool QualifiedType::hasDeclaration() const
{
    return false;
}

bool RecordType::isReferenceType() const
{
    switch (strategy)
    {
        case INTERFACE:
        case CLASS:
        case OPAQUE_CLASS:
            return true;
        case STRUCT:
            return false;
        case REPLACE:
            // If we were explicitly given a name for the replacement type,
            // then we use that text without modification.
            if (target_name.size() > 0)
            {
                return false;
            }
            return false; // TODO Is this right???
        case UNKNOWN:
        default:
            dump();
            throw std::logic_error("Haven't decided strategy for Record yet, so it is not known whether it is a reference type.");
    };
}

bool RecordType::hasDeclaration() const
{
    return true;
}

Declaration* RecordType::getDeclaration() const
{
    return getRecordDeclaration();
}

RecordDeclaration * NonTemplateRecordType::getRecordDeclaration() const
{
    const clang::Decl* clang_decl = type->getDecl();
    Declaration* d = ::getDeclaration(clang_decl);
    return dynamic_cast<RecordDeclaration*>(d);
}

bool NonTemplateRecordType::isWrappable(bool)
{
    // This is kind of a hack, since this method should really just be:
    // return getRecordDeclaration()->isWrappable()
    // but sometimes the decl is Unwrappable (usually because it's a
    // variadic template (FIXME how did this type even get created?
    // It should be a SpecializationType.))
    Declaration* d = ::getDeclaration(type->getDecl());
    return d->isWrappable();
}

RecordDeclaration* TemplateRecordType::getRecordDeclaration() const
{
    Declaration* decl = ::getDeclaration(type->getDecl());
    // TODO the declaration of an injected classname type is the
    // CXXRecordDecl inside of the ClassTemplateDecl
    // Make sure this is behaving the way I expect
    auto result = dynamic_cast<RecordDeclaration*>(decl);
    return result;
}

bool TemplateRecordType::isWrappable(bool)
{
    return getRecordDeclaration()->isWrappable();
}

bool PointerOrReferenceType::hasDeclaration() const
{
    return false;
}

Declaration* PointerOrReferenceType::getDeclaration() const
{
    // TODO assert  throw
    return nullptr;
}

Type * PointerType::getPointeeType() const
{
    return Type::get(type->getPointeeType());
}

Type * ReferenceType::getPointeeType() const
{
    return Type::get(type->getPointeeType());
}
bool ReferenceType::isReferenceType() const
{
    // TODO think about this again and add a comment
    return getPointeeType()->isReferenceType();
}

bool TypedefType::isReferenceType() const
{
    return Type::get(type->desugar())->isReferenceType();
}

bool TypedefType::hasDeclaration() const
{
    return true;
}

Declaration* TypedefType::getDeclaration() const
{
    return getTypedefDeclaration();
}

TypedefDeclaration * TypedefType::getTypedefDeclaration() const
{
    clang::TypedefNameDecl * clang_decl = type->getDecl();

    Declaration* this_declaration = ::getDeclaration(static_cast<clang::Decl*>(clang_decl));
    if( !this_declaration )
    {
        clang_decl->dump();
        std::cerr << "ERROR: Typedef does not have a declaration!\n";
        return nullptr;
    }

    return dynamic_cast<TypedefDeclaration*>(this_declaration);
}

Type* TypedefType::getTargetType() const
{
    return Type::get(type->desugar());
}

bool TypedefType::isWrappable(bool refAllowed)
{
    bool result = getTargetType()->isWrappable(refAllowed);

    // FIXME duplication with TypedefDecl
    clang::TypedefNameDecl* clang_decl = type->getDecl();
    if (clang_decl->isImplicit())
    {
        result = false;
    }
    return result;
}

bool EnumType::hasDeclaration() const
{
    return true;
}

Declaration* EnumType::getDeclaration() const
{
    return getEnumDeclaration();
}

EnumDeclaration * EnumType::getEnumDeclaration() const
{
    clang::EnumDecl * clang_decl = type->getDecl();

    Declaration* cpp_generic_decl = ::getDeclaration(static_cast<clang::Decl*>(clang_decl));
    return dynamic_cast<EnumDeclaration*>(cpp_generic_decl);
}

bool UnionType::hasDeclaration() const
{
    return true;
}

Declaration* UnionType::getDeclaration() const
{
    return getUnionDeclaration();
}
UnionDeclaration * UnionType::getUnionDeclaration() const
{
    clang::RecordDecl * clang_decl = type->getDecl();

    return dynamic_cast<UnionDeclaration*>(::getDeclaration(clang_decl));
}

bool UnionType::isWrappable(bool)
{
    return getUnionDeclaration()->isWrappable();
}

bool ArrayType::hasDeclaration() const
{
    return false;
}

Type* ConstantArrayType::getElementType() const
{
    return Type::get(type->getElementType());
}

bool ConstantArrayType::isFixedLength()
{
    return true;
}

bool ConstantArrayType::isDependentLength()
{
    return false;
}

long long ConstantArrayType::getLength()
{
    std::istringstream strm(type->getSize().toString(10, true));
    long long result;
    strm >> result;
    return result;
}

Expression* ConstantArrayType::getLengthExpression()
{
    throw std::logic_error("Not a dependent length array; length is a constant int.");
}

Type* VariableArrayType::getElementType() const
{
    return Type::get(type->getElementType());
}

bool VariableArrayType::isFixedLength()
{
    return false;
}

bool VariableArrayType::isDependentLength()
{
    return false;
}

long long VariableArrayType::getLength()
{
    throw std::logic_error("Asked for the length of a variable length area.");
}

Expression* VariableArrayType::getLengthExpression()
{
    throw std::logic_error("Not a dependent length array; length is variable.");
}

Type* DependentLengthArrayType::getElementType() const
{
    return Type::get(type->getElementType());
}

bool DependentLengthArrayType::isFixedLength()
{
    return true;
}

bool DependentLengthArrayType::isDependentLength()
{
    return true;
}

long long DependentLengthArrayType::getLength()
{
    throw std::logic_error("Asked for the length of a dependent length area.");
}

Expression* DependentLengthArrayType::getLengthExpression()
{
    return wrapClangExpression(type->getSizeExpr());
}

bool QualifiedType::isReferenceType() const
{
    return unqualifiedType()->isReferenceType();
}

bool VectorType::hasDeclaration() const
{
    return false;
}

bool TemplateArgumentType::hasDeclaration() const
{
    return true;
}

Declaration* TemplateArgumentType::getDeclaration() const
{
    return getTemplateTypeArgumentDeclaration();
}

TemplateTypeArgumentDeclaration * TemplateArgumentType::getTemplateTypeArgumentDeclaration() const
{
    assert(type->getDecl() || template_list);

    if (template_list)
    {
        const clang::NamedDecl* clang_decl = template_list->getParam(type->getIndex());
        assert(isTemplateTypeParmDecl(clang_decl));
        return dynamic_cast<TemplateTypeArgumentDeclaration*>(::getDeclaration(clang_decl));
    }
    else
    {
        const clang::TemplateTypeParmDecl* cppDecl = type->getDecl();
        Declaration* decl = ::getDeclaration(cppDecl);
        TemplateTypeArgumentDeclaration* result = dynamic_cast<TemplateTypeArgumentDeclaration*>(decl);
        return result;
    }
}

binder::string* TemplateArgumentType::getIdentifier() const
{
    std::string identifier = type->getIdentifier()->getName().str();
    return new binder::string(identifier.data(), identifier.size());
}

bool TemplateSpecializationType::hasDeclaration() const
{
    return true;
}

Declaration* TemplateSpecializationType::getDeclaration() const
{
    return getTemplateDeclaration();
}

Declaration* TemplateSpecializationType::getTemplateDeclaration() const
{
    clang::TemplateDecl* clang_decl = type->getTemplateName().getAsTemplateDecl();
    return ::getDeclaration(clang_decl);
}

unsigned TemplateSpecializationType::getTemplateArgumentCount() const
{
    return type->getNumArgs();
}

TemplateArgumentInstanceIterator* TemplateSpecializationType::getTemplateArgumentBegin() const
{
    return new TemplateArgumentInstanceIterator(type->begin());
}

TemplateArgumentInstanceIterator* TemplateSpecializationType::getTemplateArgumentEnd() const
{
    return new TemplateArgumentInstanceIterator(type->end());
}

bool TemplateSpecializationType::isWrappable(bool)
{
    // TODO check the template arguments
    if (!getTemplateDeclaration()->isWrappable()) return false;

    TemplateArgumentInstanceIterator* end = getTemplateArgumentEnd();
    for (TemplateArgumentInstanceIterator* iter = getTemplateArgumentBegin();
            !iter->equals(end);
            iter->advance())
    {
        // Can't return true in here, because all the arguments need to be OK
        switch (iter->getKind())
        {
            case TemplateArgumentInstanceIterator::Type:
                if (!iter->getType()->isWrappable(false)) return false;
                break;
            case TemplateArgumentInstanceIterator::Pack:
                return false;
            case TemplateArgumentInstanceIterator::Integer:
            case TemplateArgumentInstanceIterator::Expression:
                break;
        }
    }
    return true;
}

void TemplateSpecializationType::dump() const
{
    type->dump();
}

#define DUMP_METHOD(TYPE) \
void TYPE##Type::dump() const\
{ \
    type->dump(); \
}
DUMP_METHOD(Invalid)
void BuiltinType::dump() const
{
    type->dump();
}
DUMP_METHOD(NonTemplateRecord)
DUMP_METHOD(TemplateRecord)
DUMP_METHOD(Pointer)
DUMP_METHOD(Reference)
DUMP_METHOD(Typedef)
DUMP_METHOD(Enum)
DUMP_METHOD(Union)
DUMP_METHOD(ConstantArray)
DUMP_METHOD(VariableArray)
DUMP_METHOD(DependentLengthArray)
DUMP_METHOD(Function)
void QualifiedType::dump() const
{
    type.dump();
}
DUMP_METHOD(Vector)
DUMP_METHOD(TemplateArgument)
DUMP_METHOD(Delayed)

Type* ArgumentTypeRange::front()
{
    return Type::get(*cpp_iter);
}

Type * FunctionType::getReturnType()
{
    return Type::get(type->getReturnType());
}

ArgumentTypeRange* FunctionType::getArgumentRange()
{
    // See the clang visitor visitFunctionType()
    return new ArgumentTypeRange(type->param_types());
}

bool FunctionType::hasDeclaration() const
{
    return false;
}

class InnerNameResolver : public clang::RecursiveASTVisitor<InnerNameResolver>
{
    public:
    Type * result;
    InnerNameResolver() : result(nullptr) { }

    bool WalkUpFromDecl(clang::Decl*)
    {
        throw std::logic_error("Do not know how to refer to dependent type declaration");
    }

    bool WalkUpFromTypeDecl(clang::TypeDecl* decl)
    {
        result = Type::get(decl->getTypeForDecl());
        return false;
    }

    bool WalkUpFromTypedefDecl(clang::TypedefDecl* decl)
    {
        result = Type::get(decl->getUnderlyingType());
        return false;
    }
};

class IdentifierPathResolver : public clang::RecursiveASTVisitor<IdentifierPathResolver>
{
    public:
    Type * result;
    std::stack<const clang::IdentifierInfo*>* identifier_path;
    IdentifierPathResolver(std::stack<const clang::IdentifierInfo*>* path)
        : result(nullptr), identifier_path(path)
    { }

    bool WalkUpFromDecl(clang::Decl*)
    {
        throw std::logic_error("Do not know how to refer to dependent type declaration");
    }

    bool WalkUpFromTypedefDecl(clang::TypedefDecl* decl)
    {
        clang::QualType underlying_type = decl->getUnderlyingType();
        if (identifier_path->empty())
        {
            result = Type::get(underlying_type);
        }
        else
        {
            const clang::IdentifierInfo* next_id = identifier_path->top();
            identifier_path->pop();
            NestedNameResolver<IdentifierPathResolver> inner(next_id, identifier_path);
            inner.TraverseType(underlying_type);
            result = inner.result;
        }
        return false;
    }
};

bool NestedNameWrapper::isType() const
{
    switch (name->getKind())
    {
        case clang::NestedNameSpecifier::TypeSpec:
        case clang::NestedNameSpecifier::TypeSpecWithTemplate:
            return true;
        default:
            return false;
    }
}

bool NestedNameWrapper::isIdentifier() const
{
    switch (name->getKind())
    {
        case clang::NestedNameSpecifier::Identifier:
            return true;
        default:
            return false;
    }
}

NestedNameWrapper* NestedNameWrapper::getPrefix() const
{
    if (name->getPrefix())
    {
        return new NestedNameWrapper(name->getPrefix());
    }
    else
    {
        return nullptr;
    }
}

binder::string* NestedNameWrapper::getAsIdentifier() const
{
    return new binder::string(name->getAsIdentifier()->getNameStart(), name->getAsIdentifier()->getLength());
}

Type* NestedNameWrapper::getAsType() const
{
    assert(isType());

    return Type::get(name->getAsType());
}

Type* DelayedType::resolveType() const
{
    clang::NestedNameSpecifier* container = type->getQualifier();

    clang::NestedNameSpecifier::SpecifierKind kind = container->getKind();
    Type * result = nullptr;
    switch (kind)
    {
        case clang::NestedNameSpecifier::TypeSpec:
        case clang::NestedNameSpecifier::TypeSpecWithTemplate:
        {
            const clang::Type* container_type = container->getAsType();
            NestedNameResolver<InnerNameResolver> visitor(type->getIdentifier());
            visitor.TraverseType(clang::QualType(container_type, 0));
            result = visitor.result;
            break;
        }
        case clang::NestedNameSpecifier::Identifier:
        {
            std::stack<const clang::IdentifierInfo*> identifier_path;
            identifier_path.push(type->getIdentifier());
            const clang::NestedNameSpecifier* cur_name;
            for (cur_name = container;
                 cur_name->getKind() == clang::NestedNameSpecifier::Identifier;
                 cur_name = cur_name->getPrefix()
                )
            {
                identifier_path.push(cur_name->getAsIdentifier());
            }

            // TODO figure out how to get rid of this switch
            switch (cur_name->getKind())
            {
                case clang::NestedNameSpecifier::TypeSpec:
                case clang::NestedNameSpecifier::TypeSpecWithTemplate:
                {
                    const clang::Type* container_type = cur_name->getAsType();
                    const clang::IdentifierInfo* first_id = identifier_path.top();
                    identifier_path.pop();
                    NestedNameResolver<IdentifierPathResolver> visitor(first_id, &identifier_path);
                    visitor.TraverseType(clang::QualType(container_type, 0));
                    result = visitor.result;
                    break;
                }
                case clang::NestedNameSpecifier::Identifier:
                    throw std::logic_error("Tried to find the prefix of a nested name specifier that was not an identifier, but still have an identifier.");
                    break;
                default:
                    throw std::logic_error("Unknown nested name prefix kind");
            }
            break;
        }
        default:
            throw std::logic_error("Unknown nested name kind");
    }

    return result;
}

binder::string* DelayedType::getIdentifier() const
{
    return new binder::string(type->getIdentifier()->getNameStart(), type->getIdentifier()->getLength());
}

NestedNameWrapper* DelayedType::getQualifier() const
{
    return new NestedNameWrapper(type->getQualifier());
}

bool DelayedType::isWrappable(bool refAllowed)
{
    Type * r = resolveType();
    if (wrapping)
    {
        std::cerr << "Delayed type not wrappable because of recursion!\n";
        return false;
    }
    if (r)
    {
        wrapping = true;
        bool result = r->isWrappable(refAllowed);
        wrapping = false;
        return result;
    }
    else
    {
        //std::cerr << "Delayed type is not wrappable because it does not resolve.\n";
        // WE'LL DO IT LIVE
        return false;

        clang::NestedNameSpecifier* container = type->getQualifier();

        clang::NestedNameSpecifier::SpecifierKind kind = container->getKind();
        switch (kind)
        {
            case clang::NestedNameSpecifier::TypeSpec:
            case clang::NestedNameSpecifier::TypeSpecWithTemplate:
            {
                const clang::Type* container_type = container->getAsType();
                return Type::get(container_type)->isWrappable(false);
                break;
            }
            default:
                return true;
        }
    }
}

bool DelayedType::hasDeclaration() const
{
    //TODO This is probably not correct a lot of the time
    return false;
}

TemplateArgumentInstanceIterator::Kind TemplateArgumentInstanceIterator::getKind()
{
    switch (cpp_iter->getKind())
    {
        case clang::TemplateArgument::Type:
            return Type;
        case clang::TemplateArgument::Integral:
            return Integer;
        case clang::TemplateArgument::Expression:
            return Expression;
        case clang::TemplateArgument::Pack:
            return Pack;
        default:
            throw std::logic_error("Cannot handle other kinds of template arguments besides Type and Integral.");
    }
}

Type* TemplateArgumentInstanceIterator::getType()
{
    assert(cpp_iter->getKind() == clang::TemplateArgument::Type);

    return Type::get(cpp_iter->getAsType());
}

long long TemplateArgumentInstanceIterator::getInteger()
{
    assert(cpp_iter->getKind() == clang::TemplateArgument::Integral);

    return cpp_iter->getAsIntegral().getSExtValue();
}

Expression* TemplateArgumentInstanceIterator::getExpression()
{
    assert(cpp_iter->getKind() == clang::TemplateArgument::Expression);

    return wrapClangExpression(cpp_iter->getAsExpr());
}

void TemplateArgumentInstanceIterator::dumpPackInfo()
{
    assert(cpp_iter->getKind() == clang::TemplateArgument::Pack);

    clang::TemplateArgument expansion = cpp_iter->getPackExpansionPattern();
    std::cerr << "expansion kind = " << expansion.getKind() << "\n";
    std::cerr << "contains unexpanded parameter pack: " << cpp_iter->containsUnexpandedParameterPack() << "\n";
    std::cerr << "is pack expansion: " << cpp_iter->isPackExpansion() << "\n";
    llvm::Optional<unsigned> numExpansions = cpp_iter->getNumTemplateExpansions();
    if (numExpansions.hasValue())
    {
        std::cerr << "expansion count " << numExpansions.getValue() << "\n";
    }
    else
    {
        std::cerr << "no expansions\n";
    }
    std::cerr << "pack size: " << cpp_iter->pack_size() << "\n";
    std::cerr << "pack array size: " << cpp_iter->getPackAsArray().size() << "\n";
    std::cerr << "dependent: " << cpp_iter->isDependent() << "\n";
    std::cerr << "instantiation dependent: " << cpp_iter->isInstantiationDependent() << "\n";
}

ClangTypeVisitor::ClangTypeVisitor(const clang::PrintingPolicy* pp)
    : clang::RecursiveASTVisitor<ClangTypeVisitor>(),
    type_to_traverse(nullptr), type_in_progress(nullptr),
    printPolicy(pp)
{ }

bool ClangTypeVisitor::TraverseType(clang::QualType type)
{
    if( Type::type_map.find(type) != Type::type_map.end() )
        return true;

    bool result;
    if (type.isLocalConstQualified())
    {
        allocateQualType(type);

        clang::QualType unqual = type;
        // Qualifiers handled here also should to be handled in
        // Type::unqualifiedType()
        unqual.removeLocalConst();
        result = TraverseType(unqual);
    }
    else if (type.getTypePtrOrNull() == nullptr)
    {
        type.dump();
        throw std::runtime_error("Found a NULL type!");
        allocateInvalidType(type);
        result = true;
    }
    else if (type.isLocalRestrictQualified())
    {
        // restrict is (I think) just an optimization
        clang::QualType unqual = type;
        unqual.removeLocalRestrict();
        result = TraverseType(unqual);
        Type::type_map.insert(std::make_pair(type, Type::get(unqual)));
    }
    else if (!type.getLocalQualifiers().empty())
    {
        //std::cerr << "ERROR: Unrecognized qualifiers (\"" << type.getLocalQualifiers().getAsString() << "\") for type ";
        //type.dump();
        allocateInvalidType(type);
        result = true;
    }
    else
    {
        result = Super::TraverseType(type);
    }

    return result;
}

void ClangTypeVisitor::allocateInvalidType(const clang::QualType& t)
{
    type_in_progress = new InvalidType(t);
    Type::type_map.insert(std::make_pair(t, type_in_progress));
}

void ClangTypeVisitor::allocateQualType(const clang::QualType t)
{
    type_in_progress = new QualifiedType(t);
    Type::type_map.insert(std::make_pair(t, type_in_progress));
}

template<typename T, typename ClangType>
void ClangTypeVisitor::allocateType(const ClangType* t)
{
    type_in_progress = new T(t);
    Type::type_map.insert(std::make_pair(clang::QualType(t, 0), type_in_progress));
}

#define WALK_UP_METHOD(KIND) \
bool ClangTypeVisitor::WalkUpFrom##KIND##Type( clang::KIND##Type * type) \
{ \
    allocateType<KIND##Type>(type); \
    return Super::WalkUpFrom##KIND##Type(type); \
}
bool ClangTypeVisitor::WalkUpFromLValueReferenceType(clang::LValueReferenceType* type)
{
    allocateType<ReferenceType>(type);
    return Super::WalkUpFromLValueReferenceType(type);
}

bool ClangTypeVisitor::WalkUpFromRecordType(clang::RecordType* type)
{
    if (!type_in_progress)
    {
        if( type->isStructureType() || type->isClassType() )
        {
            allocateType<NonTemplateRecordType>(type);
        }
        else if( type->isUnionType() )
        {
            allocateType<UnionType>(type);
        }
    }
    return Super::WalkUpFromRecordType(type);
}

bool ClangTypeVisitor::WalkUpFromBuiltinType(clang::BuiltinType* type)
{
    if (type->getKind() == clang::BuiltinType::Dependent)
    {
        allocateInvalidType(clang::QualType(type, 0));
        return true;
    }
    else
    {
        allocateType<BuiltinType>(type);
        return Super::WalkUpFromBuiltinType(type);
    }
}
WALK_UP_METHOD(Pointer)

bool ClangTypeVisitor::WalkUpFromConstantArrayType(clang::ConstantArrayType* type)
{
    allocateType<ConstantArrayType>(type);
    return Super::WalkUpFromConstantArrayType(type);
}

bool ClangTypeVisitor::WalkUpFromIncompleteArrayType(clang::IncompleteArrayType* type)
{
    allocateType<VariableArrayType>(type);
    return Super::WalkUpFromIncompleteArrayType(type);
}

bool ClangTypeVisitor::WalkUpFromDependentSizedArrayType(clang::DependentSizedArrayType* type)
{
    allocateType<DependentLengthArrayType>(type);
    return Super::WalkUpFromDependentSizedArrayType(type);
}

bool ClangTypeVisitor::WalkUpFromFunctionProtoType(clang::FunctionProtoType* type)
{
    allocateType<FunctionType>(type);
    return Super::WalkUpFromFunctionProtoType(type);
}
bool ClangTypeVisitor::WalkUpFromFunctionNoProtoType(clang::FunctionNoProtoType* type)
{
    allocateInvalidType(clang::QualType(type, 0));
    return false;
}
bool ClangTypeVisitor::WalkUpFromTypedefType(clang::TypedefType* type)
{
    allocateType<TypedefType>(type);
    return Super::WalkUpFromTypedefType(type);
}

WALK_UP_METHOD(Vector)
WALK_UP_METHOD(Enum)

bool ClangTypeVisitor::WalkUpFromRValueReferenceType(clang::RValueReferenceType* type)
{
    allocateInvalidType(clang::QualType(type, 0));
    return false;
}

bool ClangTypeVisitor::WalkUpFromType(clang::Type* type)
{
    if( !type_in_progress )
    {
        allocateInvalidType(clang::QualType(type, 0));
        type->dump();
        throw std::logic_error("Can not wrap type!");
        return false;
    }

    return Super::WalkUpFromType(type);
}

bool ClangTypeVisitor::VisitBuiltinType(clang::BuiltinType* cppType)
{
    assert(printPolicy != nullptr);
    string name = cppType->getName(*printPolicy).data();
    Type::type_by_name.insert(std::make_pair(name, type_in_progress));
    return true;
}

bool ClangTypeVisitor::VisitPointerType(clang::PointerType* cppType)
{
    ClangTypeVisitor pointeeVisitor(printPolicy);
    return pointeeVisitor.TraverseType(cppType->getPointeeType());
}

bool ClangTypeVisitor::VisitRecordType(clang::RecordType* cppType)
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
        ClangTypeVisitor field_visitor(printPolicy);
        for( clang::RecordDecl::field_iterator iter = decl->field_begin();
                iter != end && continue_traversal; ++iter )
        {
            field_visitor.reset();
            continue_traversal = field_visitor.TraverseType(iter->getType());
        }
    }

    return continue_traversal;
}

bool ClangTypeVisitor::VisitArrayType(clang::ArrayType* cppType)
{
    ClangTypeVisitor element_visitor(printPolicy);
    return element_visitor.TraverseType(cppType->getElementType());
}

bool ClangTypeVisitor::VisitFunctionType(clang::FunctionType* cppType)
{
    bool continue_traversal = true;
    ClangTypeVisitor arg_visitor(printPolicy); // Also visits return type
    continue_traversal = arg_visitor.TraverseType(cppType->getReturnType());

    // TODO get all the arguments? or does that happen in traverse?

    return continue_traversal;
}

bool ClangTypeVisitor::VisitLValueReferenceType(clang::LValueReferenceType* cppType)
{
    ClangTypeVisitor target_visitor(printPolicy);
    return target_visitor.TraverseType(cppType->getPointeeType());
}

bool ClangTypeVisitor::VisitTypedefType(clang::TypedefType* cppType)
{
    ClangTypeVisitor real_visitor(printPolicy);
    return real_visitor.TraverseType(cppType->desugar());
}

bool ClangTypeVisitor::WalkUpFromElaboratedType(clang::ElaboratedType* type)
{
    //bool result = TraverseType(type->getNamedType());
    // TODO nullptr
    Type* t = Type::get(type->getNamedType(), printPolicy);
    // FIXME does this really need to go into the map here?  Does that happen during TraverseType?
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), t));
    type_in_progress = t;
    return Super::WalkUpFromElaboratedType(type);
}

bool ClangTypeVisitor::WalkUpFromDecayedType(clang::DecayedType* type)
{
    bool result = TraverseType(type->getDecayedType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getDecayedType())->second;
    // FIXME does this really need to go into the map here?  Does that happen during TraverseType?
    Type::type_map.insert(std::make_pair(type->getDecayedType(), t));
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), t));
    return result;
}

bool ClangTypeVisitor::WalkUpFromParenType(clang::ParenType* type)
{
    bool result = TraverseType(type->getInnerType());
    // TODO nullptr
    Type* t = Type::type_map.find(type->getInnerType())->second;
    // FIXME does this really need to go into the map here?
    Type::type_map.insert(std::make_pair(type->getInnerType(), t));
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), t));
    return result;
}

bool ClangTypeVisitor::WalkUpFromDecltypeType(clang::DecltypeType* type)
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

bool ClangTypeVisitor::WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type)
{
    // TODO
    allocateType<TemplateSpecializationType>(type);
    std::string name = type->getTemplateName().getAsTemplateDecl()->getQualifiedNameAsString();
    // TODO Make sure I'm not making too many of these!
    string binder_name(name.c_str(), name.size());
    Type::type_by_name.insert(std::make_pair(binder_name, type_in_progress));
    return Super::WalkUpFromTemplateSpecializationType(type);
}

bool ClangTypeVisitor::WalkUpFromTemplateTypeParmType(clang::TemplateTypeParmType* type)
{
    allocateType<TemplateArgumentType>(type);
    return Super::WalkUpFromTemplateTypeParmType(type);
}

bool ClangTypeVisitor::VisitTemplateTypeParmType(clang::TemplateTypeParmType* type)
{
    clang::TemplateTypeParmDecl* decl = type->getDecl();
    if (decl)
    {
        DeclVisitor visitor(printPolicy);
        // TraverseDecl simply returns if this decl has already been reached,
        // so no need to worry about mutual recursion
        visitor.TraverseDecl(decl);
    }

    return Super::VisitTemplateTypeParmType(type);
}

// A non-instantiated class template
bool ClangTypeVisitor::WalkUpFromInjectedClassNameType(clang::InjectedClassNameType* type)
{
    // FIXME what if the template is a union?
    // I don't translate those just yet...
    allocateType<TemplateRecordType>(type);
    return Super::WalkUpFromInjectedClassNameType(type);
}

bool ClangTypeVisitor::WalkUpFromDependentNameType(clang::DependentNameType* type)
{
    allocateType<DelayedType>(type);
    return Super::WalkUpFromDependentNameType(type);
}

bool ClangTypeVisitor::WalkUpFromTypeOfExprType(clang::TypeOfExprType* type)
{
    Type * deduced = Type::get(type->getUnderlyingExpr()->getType(), printPolicy);
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), deduced));
    return true;
}

bool ClangTypeVisitor::WalkUpFromSubstTemplateTypeParmType(clang::SubstTemplateTypeParmType* type)
{
    Type* underneath = Type::get(type->desugar(), printPolicy);
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), underneath));
    return true;
}

bool ClangTypeVisitor::WalkUpFromUnaryTransformType(clang::UnaryTransformType* type)
{
    allocateInvalidType(clang::QualType(type, 0));
    return false;
}

bool ClangTypeVisitor::WalkUpFromDependentTemplateSpecializationType(clang::DependentTemplateSpecializationType* type)
{
    allocateInvalidType(clang::QualType(type, 0));
    return false;
}

bool ClangTypeVisitor::WalkUpFromMemberPointerType(clang::MemberPointerType* type)
{
    allocateInvalidType(clang::QualType(type, 0));
    return false;
}

bool ClangTypeVisitor::WalkUpFromPackExpansionType(clang::PackExpansionType* type)
{
    allocateInvalidType(clang::QualType(type, 0));
    return false;
}


bool ClangTypeVisitor::WalkUpFromAutoType(clang::AutoType* type)
{
    Type * deduced = Type::get(type->getDeducedType(), printPolicy);
    Type::type_map.insert(std::make_pair(clang::QualType(type, 0), deduced));
    return true;
}
