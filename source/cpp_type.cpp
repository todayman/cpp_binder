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
        std::cerr << "WARNING: Attempted to look up a QualType that has a null Type pointer\n";
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

bool QualifiedType::isConst() const
{
    return type.isLocalConstQualified();
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
            ;
    };
}
Declaration* RecordType::getDeclaration() const
{
    return getRecordDeclaration();
}

RecordDeclaration * NonTemplateRecordType::getRecordDeclaration() const
{
    return dynamic_cast<RecordDeclaration*>(::getDeclaration(type->getDecl()));
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
    return getTypedefDeclaration()->getTargetType()->isReferenceType();
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
        std::cerr << clang_decl->isImplicit() << "\n";
        std::cerr << "type kind = " << type->getTypeClassName() << "\n";
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
    clang::EnumDecl * clang_decl = type->getDecl();

    Declaration* cpp_generic_decl = ::getDeclaration(static_cast<clang::Decl*>(clang_decl));
    return dynamic_cast<EnumDeclaration*>(cpp_generic_decl);
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

Type* ConstantArrayType::getElementType()
{
    return Type::get(type->getElementType());
}

bool ConstantArrayType::isFixedLength()
{
    return true;
}

long long ConstantArrayType::getLength()
{
    std::istringstream strm(type->getSize().toString(10, true));
    long long result;
    strm >> result;
    return result;
}

Type* VariableArrayType::getElementType()
{
    return Type::get(type->getElementType());
}

bool VariableArrayType::isFixedLength()
{
    return false;
}

long long VariableArrayType::getLength()
{
    throw std::logic_error("Asked for the length of a variable length area.");
}

bool QualifiedType::isReferenceType() const
{
    return unqualifiedType()->isReferenceType();
}

Declaration* TemplateArgumentType::getDeclaration() const
{
    return getTemplateTypeArgumentDeclaration();
}

TemplateTypeArgumentDeclaration * TemplateArgumentType::getTemplateTypeArgumentDeclaration() const
{
    assert(template_list != nullptr);

    const clang::NamedDecl* clang_decl = template_list->getParam(type->getIndex());
    assert(isTemplateTypeParmDecl(clang_decl));
    return dynamic_cast<TemplateTypeArgumentDeclaration*>(::getDeclaration(clang_decl));
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

TemplateArgumentInstanceIterator* TemplateSpecializationType::getTemplateArgumentBegin()
{
    return new TemplateArgumentInstanceIterator(type->begin());
}

TemplateArgumentInstanceIterator* TemplateSpecializationType::getTemplateArgumentEnd()
{
    return new TemplateArgumentInstanceIterator(type->end());
}

#define DUMP_METHOD(TYPE) \
void TYPE##Type::dump() const\
{ \
    type->dump(); \
}
DUMP_METHOD(Invalid)
DUMP_METHOD(Builtin)
DUMP_METHOD(NonTemplateRecord)
DUMP_METHOD(TemplateRecord)
DUMP_METHOD(Pointer)
DUMP_METHOD(Reference)
DUMP_METHOD(Typedef)
DUMP_METHOD(Enum)
DUMP_METHOD(Union)
DUMP_METHOD(ConstantArray)
DUMP_METHOD(VariableArray)
DUMP_METHOD(Function)
void QualifiedType::dump() const
{
    type.dump();
}
DUMP_METHOD(Vector)
DUMP_METHOD(TemplateArgument)
DUMP_METHOD(TemplateSpecialization)
DUMP_METHOD(Delayed)

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

class NestedNameResolver : public clang::RecursiveASTVisitor<NestedNameResolver>
{
    public:
    Type * result;
    const clang::IdentifierInfo* identifier;
    llvm::ArrayRef<clang::TemplateArgument> template_args;
    NestedNameResolver(const clang::IdentifierInfo* id)
        : result(nullptr), identifier(id), template_args()
    { }

    // WalkUpFrom*Type is used to find the Decl for that type
    // Whenever we return from one of the WalkUpMethods, we either succeeded
    // or failed, so the traversal is done (return false)
    bool WalkUpFromType(clang::Type*)
    {
        throw std::logic_error("Don't know how to resolve dependent names in this type");
    }

    bool WalkUpFromRecordType(clang::RecordType* type)
    {
        return TraverseDecl(type->getDecl());
    }

    bool WalkUpFromTypedefType(clang::TypedefType* type)
    {
        return TraverseType(type->desugar());
    }

    bool WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type)
    {
        // FIXME I am not doing argument substitution or finding the right
        // specialization here
        clang::TemplateName template_name = type->getTemplateName();
        template_args = llvm::ArrayRef<clang::TemplateArgument>(type->getArgs(), type->getNumArgs());
        return TraverseDecl(template_name.getAsTemplateDecl());
    }

    // WalkUpFrom*Decl is used to get the final dependent Type from that Decl
    bool WalkUpFromDecl(clang::Decl*)
    {
        throw std::logic_error("Don't know how to resolve a dependent type name from this decl");
    }

    bool WalkUpFromClassTemplateDecl(clang::ClassTemplateDecl* decl)
    {
        if (template_args.data())
        {
            void* insertPos = nullptr;
            clang::ClassTemplateSpecializationDecl* specialization =
                decl->findSpecialization(template_args, insertPos);
            if (specialization)
            {
                return TraverseDecl(specialization);
            }
            else
            {
                // TODO all of this logic is probably completely wrong and we
                // should just throw an exception here, but I want to get the
                // code into git before deleting it
                std::cerr << "Could not find specialization for types:\n";
                for (clang::TemplateArgument arg : template_args)
                {
                    std::cerr << "\tkind: " << arg.getKind();
                    if (arg.getKind() == clang::TemplateArgument::Type)
                    {
                        std::cerr << "\ttype is: " << arg.getAsType().getAsOpaquePtr() << "\t";
                        arg.getAsType().dump();
                        std::cerr << "\t" << arg.getAsType().getTypePtr()->getTypeClassName();
                    }
                    std::cerr << "\n";
                }
                clang::ClassTemplatePartialSpecializationDecl* partial =
                    decl->findPartialSpecialization(template_args, insertPos);
                std::cerr << "Partial specialization: " << partial << "\n";
                // If we cannot find the specialization declaration, that means
                // that the template was not instantiated with these arguments
                // anywhere, so the arguments are unsubstituted template
                // parameters.  Right?
                // TODO partial specializations
                return TraverseDecl(decl->getTemplatedDecl());
            }
        }
        else
        {
            return TraverseDecl(decl->getTemplatedDecl());
        }
    }

    bool lookupInContext(clang::DeclContext* ctx)
    {
        clang::DeclContextLookupResult lookup_result = ctx->lookup(identifier);
        if (lookup_result.size() == 0)
        {
            return false;
        }
        else if (lookup_result.size() > 1)
        {
            throw std::logic_error("Did not find exactly one result looking up a dependent type");
        }

        // This basically does the "check if a type declaration, then get type"
        InnerNameResolver inner;
        inner.TraverseDecl(lookup_result[0]);
        result = inner.result;
        return true;
    }

    bool WalkUpFromRecordDecl(clang::RecordDecl* decl)
    {
        lookupInContext(decl);
        return false;
    }

    bool WalkUpFromCXXRecordDecl(clang::CXXRecordDecl* decl)
    {
        if (lookupInContext(decl) && !result)
        {
            // This means we found the clang decl but couldn't translate it
            // So just make a thing with the right name and hope it works
            clang::DeclContextLookupResult lookup_result = decl->lookup(identifier);
            lookup_result[0]->dump();
            InnerNameResolver inner;
            inner.TraverseDecl(lookup_result[0]);
            throw std::logic_error("Couldn't translate the dependent type");
        }
        if (!result)
        {
            // TODO This is not quite following the C++ name resolution rules,
            // because I'm probably looking at private members in superclasses,
            // especially in the wrong order.
            for (clang::CXXRecordDecl::base_class_iterator iter = decl->bases_begin(),
                    finish = decl->bases_end();
                 iter != finish;
                 ++iter)
            {
                TraverseType(iter->getType());
                if (result)
                {
                    break;
                }
            }

            //if (!result)
            //{
            //    std::cerr << "Could not find \"" << identifier->getName().str() << "\" in\n";
            //    decl->dump();
            //    throw std::logic_error("Could not resolve dependent type");
            //}
        }
        return false;
    }
};

Type* DelayedType::resolveType() const
{
    clang::NestedNameSpecifier* container = type->getQualifier();

    clang::NestedNameSpecifier::SpecifierKind kind = container->getKind();
    Type * result = nullptr;
    switch (kind)
    {
        case clang::NestedNameSpecifier::TypeSpec:
        {
            const clang::Type* container_type = container->getAsType();
            NestedNameResolver visitor(type->getIdentifier());
            visitor.TraverseType(clang::QualType(container_type, 0));
            result = visitor.result;
            break;
        }
        default:
            throw std::logic_error("Unknown nested name kind");
    }

    /*if (!result)
    {
        // ***** **. We're doing it live!
        binder::string empty;
        chooseReplaceStrategy(&empty);
        result = this;
    }*/
    return result;
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
        std::cerr << "ERROR: Unrecognized qualifiers (\"" << type.getLocalQualifiers().getAsString() << "\") for type ";
        type.dump();
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
    if( type->isStructureType() || type->isClassType() )
    {
        allocateType<NonTemplateRecordType>(type);
    }
    else if( type->isUnionType() )
    {
        allocateType<UnionType>(type);
    }
    return Super::WalkUpFromRecordType(type);
}
WALK_UP_METHOD(Builtin)
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
    allocateInvalidType(clang::QualType(type, 0));
    return false;
}

WALK_UP_METHOD(Function)
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
