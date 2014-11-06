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

#include <iostream>
#include <set>

#include <boost/filesystem.hpp>

#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/SourceManager.h"

#include "cpp_type.hpp"
#include "cpp_decl.hpp"

#include "clang/AST/Decl.h"

Visibility accessSpecToVisibility(clang::AccessSpecifier as)
{
    switch( as )
    {
        case clang::AS_public:
            return ::PUBLIC;
        case clang::AS_private:
            return ::PRIVATE;
        case clang::AS_protected:
            return ::PROTECTED;
        case clang::AS_none:
            // This means different things in different contexts,
            // and I don't know what any of them are.
            throw 29;
        default:
            throw 30;
    }
}

bool isCXXRecord(const clang::Decl* decl)
{
    // This set is of all the DeclKinds that are subclasses of CXXRecord
    #define ABSTRACT_DECL(Type)
    #define DECL(Type, Base)
    #define CXXRECORD(Type, Base)   clang::Decl::Type,
    static std::unordered_set<int> CXXRecordKinds({
    #include "clang/AST/DeclNodes.inc"
            });
    #undef CXXRECORD
    #undef DECL
    #undef ABSTRACT_DECL
    return CXXRecordKinds.count(decl->getKind()) > 0;
}
bool isNamedDecl(const clang::Decl* decl)
{
    // This set is of all the DeclKinds that are subclasses of CXXRecord
    #define ABSTRACT_DECL(Type)
    #define DECL(Type, Base)
    #define NAMED(Type, Base)   clang::Decl::Type,
    static std::unordered_set<int> NamedKinds({
    #include "clang/AST/DeclNodes.inc"
            });
    #undef NAMED
    #undef DECL
    #undef ABSTRACT_DECL
    return NamedKinds.count(decl->getKind()) > 0;
}
bool isCXXMethodDecl(const clang::Decl* decl)
{
    // This set is of all the DeclKinds that are subclasses of CXXRecord
    #define ABSTRACT_DECL(Type)
    #define DECL(Type, Base)
    #define CXXMETHOD(Type, Base)   clang::Decl::Type,
    static std::unordered_set<int> CXXMethodKinds({
    #include "clang/AST/DeclNodes.inc"
            });
    #undef CXXMETHOD
    #undef DECL
    #undef ABSTRACT_DECL
    return CXXMethodKinds.count(decl->getKind()) > 0;
}

std::unordered_map<clang::Decl*, Declaration*> DeclVisitor::declarations;
std::unordered_set<Declaration*> DeclVisitor::free_declarations;

void printPresumedLocation(const clang::NamedDecl* Declaration)
{
    clang::SourceLocation source_loc = Declaration->getLocation();
    clang::PresumedLoc presumed = source_manager->getPresumedLoc(source_loc);

    std::cout << Declaration->getNameAsString() << " at " << presumed.getFilename() << ":" << presumed.getLine() << "\n";
}

/*template<typename ClangType, typename TranslatorType>
TranslatorType* Iterator<ClangType, TranslatorType>::operator*()
{
    auto search_result = DeclVisitor::getDeclarations().find(*cpp_iter);
    if( search_result == DeclVisitor::getDeclarations().end() )
    {
        (*cpp_iter)->dump();
        throw std::runtime_error("Lookup failed!");
    }
    Declaration* decl = search_result->second;
    return dynamic_cast<TranslatorType*>(decl);
}*/
//template Declaration* Iterator<clang::DeclContext::decl_iterator, Declaration>::operator*();
Declaration* DeclarationIterator::operator*()
{
    auto search_result = DeclVisitor::getDeclarations().find(*cpp_iter);
    if( search_result == DeclVisitor::getDeclarations().end() )
    {
        (*cpp_iter)->dump();
        throw std::runtime_error("Lookup failed!");
    }
    Declaration* decl = search_result->second;
    return dynamic_cast<Declaration*>(decl);
}
//template ArgumentDeclaration* Iterator<clang::FunctionDecl::param_const_iterator, ArgumentDeclaration>::operator*();
ArgumentDeclaration* ArgumentIterator::operator*()
{
    auto search_result = DeclVisitor::getDeclarations().find(*cpp_iter);
    if( search_result == DeclVisitor::getDeclarations().end() )
    {
        (*cpp_iter)->dump();
        throw std::runtime_error("Lookup failed!");
    }
    Declaration* decl = search_result->second;
    return dynamic_cast<ArgumentDeclaration*>(decl);
}
//template FieldDeclaration* Iterator<clang::RecordDecl::field_iterator, FieldDeclaration>::operator*();
FieldDeclaration* FieldIterator::operator*()
{
    auto search_result = DeclVisitor::getDeclarations().find(*cpp_iter);
    if( search_result == DeclVisitor::getDeclarations().end() )
    {
        (*cpp_iter)->dump();
        throw std::runtime_error("Lookup failed!");
    }
    Declaration* decl = search_result->second;
    return dynamic_cast<FieldDeclaration*>(decl);
}
//template MethodDeclaration* Iterator<clang::CXXRecordDecl::method_iterator, MethodDeclaration>::operator*();
MethodDeclaration* MethodIterator::operator*()
{
    auto search_result = DeclVisitor::getDeclarations().find(*cpp_iter);
    if( search_result == DeclVisitor::getDeclarations().end() )
    {
        (*cpp_iter)->dump();
        throw std::runtime_error("Lookup failed!");
    }
    Declaration* decl = search_result->second;
    MethodDeclaration * result = dynamic_cast<MethodDeclaration*>(decl);
    return result;
}
//template<>
//Superclass* Iterator<clang::CXXRecordDecl::base_class_const_iterator, Superclass>::operator*()
Superclass* SuperclassIterator::operator*()
{
    const clang::CXXBaseSpecifier * base = cpp_iter;
    Superclass * result = new Superclass;
    result->isVirtual = base->isVirtual();
    result->visibility = accessSpecToVisibility(base->getAccessSpecifier());

    result->base = Type::get(base->getType());

    return result;
}

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

DeclVisitor::DeclVisitor(const clang::PrintingPolicy* pp)
    : Super(), top_level_decls(false), decl_in_progress(nullptr), print_policy(pp)
{ }

bool DeclVisitor::registerDeclaration(clang::Decl* cppDecl, bool top_level)
{
    bool result = true;
    auto search_result = declarations.find(cppDecl);
    if( search_result == declarations.end() )
    {
        DeclVisitor next_visitor(print_policy);
        next_visitor.top_level_decls = top_level;
        result = next_visitor.TraverseDecl(cppDecl);
    }
    else if( top_level && !free_declarations.count(search_result->second) )
    {
        free_declarations.insert(search_result->second);
    }

    return result;
}

#define TRAVERSE_PART(Title, TYPE, field) \
bool DeclVisitor::Traverse##Title##Helper(TYPE* context, bool top_level) \
{ \
    bool result = true; \
    auto end = context->field##_end(); \
    for( auto iter = context->field##_begin(); \
         iter != end && result; \
         ++iter ) \
    { \
        result = registerDeclaration(*iter, top_level); \
    } \
    return result; \
}

bool DeclVisitor::TraverseDeclContext(clang::DeclContext* context, bool top_level)
{
    bool result = true;
    clang::DeclContext::decl_iterator end = context->decls_end();
    for( clang::DeclContext::decl_iterator iter = context->decls_begin();
         iter != end && result;
         ++iter )
    {
        result = registerDeclaration(*iter, top_level);
    }

    return result;
}

bool DeclVisitor::TraverseDecl(clang::Decl * Declaration)
{
    if( !Declaration ) // FIXME sometimes Declaration is null.  I don't know why.
        return true;

    if( Declaration->isTemplateDecl() )
    {
        allocateDeclaration<clang::Decl, UnwrappableDeclaration>(Declaration);
    }
    else
    {
        if( declarations.find(Declaration) != declarations.end() )
        {
            return true;
        }
        try {
            RecursiveASTVisitor<DeclVisitor>::TraverseDecl(Declaration);
        }
        catch( SkipUnwrappableType& e)
        {
            if( decl_in_progress )
            {
                decl_in_progress->markUnwrappable();
            }
            else
            {
                allocateDeclaration<clang::Decl, UnwrappableDeclaration>(Declaration);
            }
        }
    }

    return true;
}

bool DeclVisitor::TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration)
{
    allocateDeclaration<clang::Decl, UnwrappableDeclaration>(declaration);
    return true;
}

bool DeclVisitor::TraverseClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* declaration)
{
    allocateDeclaration<clang::Decl, UnwrappableDeclaration>(declaration);
    return true;
}

TRAVERSE_PART(Field, clang::CXXRecordDecl, field)
TRAVERSE_PART(Method, clang::CXXRecordDecl, method)
TRAVERSE_PART(Ctor, clang::CXXRecordDecl, ctor)

bool DeclVisitor::TraverseCXXRecordDecl(clang::CXXRecordDecl* cppDecl)
{
    if( !WalkUpFromCXXRecordDecl(cppDecl) ) return false;

    if( !TraverseDeclContext(cppDecl, false) ) return false;
    if( !TraverseFieldHelper(cppDecl, false) ) return false;
    if( !TraverseMethodHelper(cppDecl, false) ) return false;
    if( !TraverseCtorHelper(cppDecl, false) ) return false;

    return true;
}

bool DeclVisitor::TraverseCXXMethodDecl(clang::CXXMethodDecl* cppDecl)
{
    // FIXME hack to avoid translating out-of-line methods
    bool old_top_level = top_level_decls;
    top_level_decls = false; // method are never top level
    const clang::CXXRecordDecl * parent_decl = cppDecl->getParent();
    if( hasTemplateParent(parent_decl) || cppDecl->isDeleted() )
    {
        allocateDeclaration<clang::Decl, UnwrappableDeclaration>(cppDecl);
        return true;
    }

    bool result = true;
    try {
        if( !WalkUpFromCXXMethodDecl(cppDecl) )
        {
            decl_in_progress->markUnwrappable();
            return false;
        }

        // Notice that we don't traverse the body of the function
        for( clang::ParmVarDecl** iter = cppDecl->param_begin();
             result && iter != cppDecl->param_end();
             iter++ )
        {
            result = registerDeclaration(*iter);
        }
    }
    catch( SkipUnwrappableDeclaration& e )
    {
        // If we can't wrap the return type or any of the arguments,
        // then we cannot wrap the method declaration
        decl_in_progress->markUnwrappable();
    }
    // FIXME hack to avoid translating out-of-line methods
    top_level_decls = old_top_level;

    return result;
}

bool DeclVisitor::TraverseCXXConstructorDecl(clang::CXXConstructorDecl* cppDecl)
{
    const clang::CXXRecordDecl * parent_decl = cppDecl->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<DeclVisitor>::TraverseCXXConstructorDecl(cppDecl);
    }
    else
    {
        allocateDeclaration<clang::Decl, UnwrappableDeclaration>(cppDecl);
    }

    return true;
}

bool DeclVisitor::TraverseCXXDestructorDecl(clang::CXXDestructorDecl* cppDecl)
{
    const clang::CXXRecordDecl * parent_decl = cppDecl->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<DeclVisitor>::TraverseCXXDestructorDecl(cppDecl);
    }
    else
    {
        allocateDeclaration<clang::Decl, UnwrappableDeclaration>(cppDecl);
    }

    return true;
}

bool DeclVisitor::WalkUpFromDecl(clang::Decl* cppDecl)
{
    if( !decl_in_progress )
    {
        cppDecl->dump();
        throw SkipUnwrappableDeclaration(cppDecl);
    }
    return Super::WalkUpFromDecl(cppDecl);
}

bool DeclVisitor::TraverseFunctionDecl(clang::FunctionDecl * cppDecl)
{
    if( !WalkUpFromFunctionDecl(cppDecl) ) return false;
    // Notice that we don't traverse the body of the function
    // Traverse the argument declarations
    for( clang::ParmVarDecl** iter = cppDecl->param_begin();
         iter != cppDecl->param_end();
         iter++ )
    {
        registerDeclaration(*iter);
    }

    return true;
}

bool DeclVisitor::TraverseTranslationUnitDecl(clang::TranslationUnitDecl* cppDecl)
{
    top_level_decls = true;
    bool result = TraverseDeclContext(cppDecl, true);
    top_level_decls = false;
    return result;
}

bool DeclVisitor::TraverseNamespaceDecl(clang::NamespaceDecl* cppDecl)
{
    bool result = WalkUpFromNamespaceDecl(cppDecl);
    if( result )
    {
        result = TraverseDeclContext(cppDecl, false);
    }

    return result;
}

bool DeclVisitor::TraverseLinkageSpecDecl(clang::LinkageSpecDecl* cppDecl)
{
    return TraverseDeclContext(cppDecl, top_level_decls);
}

bool DeclVisitor::TraverseEnumDecl(clang::EnumDecl* cppDecl)
{
    bool result = true;
    result = WalkUpFromEnumDecl(cppDecl);
    for( clang::EnumDecl::enumerator_iterator iter = cppDecl->enumerator_begin();
         result && iter != cppDecl->enumerator_end();
         ++iter)
    {
        result = registerDeclaration(*iter);
    }
    return result;
}

bool DeclVisitor::TraverseVarDecl(clang::VarDecl* cppDecl)
{
    return WalkUpFromVarDecl(cppDecl);
}

// TODO wrap these as public imports / aliases?
bool DeclVisitor::TraverseUsingDirectiveDecl(clang::UsingDirectiveDecl* cppDecl)
{
    allocateDeclaration<clang::Decl, UnwrappableDeclaration>(cppDecl);
    return true;
}

#define UNWRAPPABLE_TRAVERSE(Type) \
bool DeclVisitor::Traverse##Type##Decl(clang::Type##Decl* cppDecl) \
{ \
    allocateDeclaration<clang::Decl, UnwrappableDeclaration>(cppDecl); \
    return true; \
}
UNWRAPPABLE_TRAVERSE(Empty)
UNWRAPPABLE_TRAVERSE(AccessSpec)
UNWRAPPABLE_TRAVERSE(Friend)
UNWRAPPABLE_TRAVERSE(StaticAssert)

// TODO properly wrap these with an alias?
// From the clang documentation on IndirectFieldDecl:
//  An instance of this class is created to represent a field injected from an
//  anonymous union/struct into the parent scope. IndirectFieldDecl are always
//  implicit.
UNWRAPPABLE_TRAVERSE(IndirectField)

UNWRAPPABLE_TRAVERSE(Using) // FIXME we can translate these as aliases
UNWRAPPABLE_TRAVERSE(UsingShadow) // FIXME we can probably translate these as aliases?

bool DeclVisitor::WalkUpFromFunctionDecl(clang::FunctionDecl* cppDecl)
{
    // This could be a method or a regular function
    if( !decl_in_progress )
        allocateDeclaration<clang::FunctionDecl, FunctionDeclaration>(cppDecl);
    return Super::WalkUpFromFunctionDecl(cppDecl);
}

bool DeclVisitor::WalkUpFromVarDecl(clang::VarDecl* cppDecl)
{
    // This could be an instance variable or a global
    if( !decl_in_progress )
        allocateDeclaration<clang::VarDecl, VariableDeclaration>(cppDecl);
    return Super::WalkUpFromVarDecl(cppDecl);
}

#define WALK_UP(C, D)\
bool DeclVisitor::WalkUpFrom##C##Decl(clang::C##Decl* cppDecl) \
{ \
    if( !decl_in_progress ) \
        allocateDeclaration<clang::C##Decl, D##Declaration>(cppDecl); \
    return Super::WalkUpFrom##C##Decl(cppDecl); \
}
WALK_UP(Typedef, Typedef)
WALK_UP(Namespace, Namespace)
WALK_UP(CXXMethod, Method)
WALK_UP(CXXConstructor, Constructor)
WALK_UP(CXXDestructor, Destructor)
WALK_UP(ParmVar, Argument)
WALK_UP(Enum, Enum)
WALK_UP(EnumConstant, EnumConstant)
WALK_UP(Field, Field)

bool DeclVisitor::VisitParmVarDecl(clang::ParmVarDecl* cppDecl)
{
    return TraverseType(cppDecl->getType());
}

bool DeclVisitor::WalkUpFromRecordDecl(clang::RecordDecl* cppDecl)
{
    if( cppDecl->isUnion() )
    {
        allocateDeclaration<clang::RecordDecl, UnionDeclaration>(cppDecl);
    }
    else if( cppDecl->isStruct() || cppDecl->isClass() )
    {
        allocateDeclaration<clang::RecordDecl, RecordDeclaration>(cppDecl);
    }
    else {
        // There's no logic to deal with these; we shouldn't reach here.
        throw SkipUnwrappableDeclaration(cppDecl);
    }

    return Super::WalkUpFromRecordDecl(cppDecl);
}

// This method is called after WalkUpFromDecl, which
// throws an exception if decl_in_progress hasn't been allocated yet.
bool DeclVisitor::VisitDecl(clang::Decl* Declaration)
{
    Visibility v = UNSET;
    switch( Declaration->getAccess() )
    {
        case clang::AS_public:
            v = PUBLIC;
            break;
        case clang::AS_protected:
            v = PROTECTED;
            break;
        case clang::AS_private:
            v = PRIVATE;
            break;
        case clang::AS_none:
            v = UNSET;
            break;
    }
    decl_in_progress->setVisibility(v);

    return Super::VisitDecl(Declaration);
}

bool DeclVisitor::VisitFunctionDecl(clang::FunctionDecl* cppDecl)
{
    return TraverseType(cppDecl->getReturnType());
}

bool DeclVisitor::VisitTypedefDecl(clang::TypedefDecl* cppDecl)
{
    clang::QualType undertype = cppDecl->getUnderlyingType();
    return TraverseType(undertype);
}

bool DeclVisitor::VisitNamedDecl(clang::NamedDecl* cppDecl)
{
    decl_in_progress->setSourceName(cppDecl->getNameAsString().c_str());
    return true;
}

bool DeclVisitor::VisitFieldDecl(clang::FieldDecl* cppDecl)
{
    return TraverseType(cppDecl->getType());
}

class FilenameVisitor : public clang::RecursiveASTVisitor<FilenameVisitor>
{
    public:
    Declaration* maybe_emits;
    std::set<boost::filesystem::path> filenames;

    template<typename ConstIterator>
    FilenameVisitor(ConstIterator firstFile, ConstIterator lastFile)
        : filenames(firstFile, lastFile)
    { }

    bool WalkUpFromNamedDecl(clang::NamedDecl* cppDecl)
    {
        clang::SourceLocation source_loc = cppDecl->getLocation();
        clang::PresumedLoc presumed = source_manager->getPresumedLoc(source_loc);

        if( presumed.getFilename() )
        {
            std::string this_filename = presumed.getFilename();
            for( auto name : filenames )
            {
                if( boost::filesystem::equivalent(name, this_filename) )
                {
                    maybe_emits->shouldBind(true);
                }
            }
        }

        return false;
    }

    bool WalkUpFromDecl(clang::Decl*)
    {
        return false;
    }
};

void enableDeclarationsInFiles(size_t count, const char ** filenames)
{
    std::vector<std::string> vec;
    vec.reserve(count);
    for( size_t i = 0; i < count; ++i)
    {
        vec.emplace_back(filenames[i]);
    }
    DeclVisitor::enableDeclarationsInFiles(vec);
}
void DeclVisitor::enableDeclarationsInFiles(const std::vector<std::string>& filename_vec)
{
    // There's no easy way to tell if a Decl is a NamedDecl,
    // so we have this special visitor that does work in WalkUpFromNamedDecl,
    // then aborts the traversal, and just aborts everything else
    FilenameVisitor visitor(begin(filename_vec), end(filename_vec));

    for( auto decl_pair : DeclVisitor::declarations )
    {
        clang::Decl * cppDecl = decl_pair.first;
        visitor.maybe_emits = decl_pair.second;
        if( visitor.maybe_emits )
            visitor.TraverseDecl(cppDecl);
    }
}

void arrayOfFreeDeclarations(size_t* count, Declaration*** array)
{
    if( !count || !array )
        throw std::logic_error("Arguments are out parameters, they cannot be null");
    (*count) = DeclVisitor::free_declarations.size();
    (*array) = new Declaration*[DeclVisitor::free_declarations.size()];

    size_t counter = 0;
    for( Declaration* decl : DeclVisitor::free_declarations )
    {
        (*array)[counter] = decl;
        counter ++;
    }
}

Declaration * getDeclaration(clang::Decl* decl)
{
    auto search_result = DeclVisitor::declarations.find(decl);
    if( search_result == DeclVisitor::declarations.end() )
    {
        return nullptr;
    }
    else
    {
        return search_result->second;
    }
}
