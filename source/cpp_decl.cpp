#include <iostream>
#include <set>

#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/SourceManager.h"

#include "cpp_type.hpp"
#include "cpp_decl.hpp"

using namespace cpp;

std::unordered_map<clang::Decl*, std::shared_ptr<Declaration>> DeclVisitor::declarations;

void printPresumedLocation(const clang::NamedDecl* Declaration)
{
    clang::SourceLocation source_loc = Declaration->getLocation();
    clang::PresumedLoc presumed = source_manager->getPresumedLoc(source_loc);

    std::cout << Declaration->getNameAsString() << " at " << presumed.getFilename() << ":" << presumed.getLine() << "\n";
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
    : Super(), decl_in_progress(nullptr), print_policy(pp)
{ }

bool DeclVisitor::registerDeclaration(clang::Decl* cppDecl)
{
    bool result = true;
    if( declarations.find(cppDecl) == declarations.end() )
    {
        DeclVisitor next_visitor(print_policy);
        result = next_visitor.TraverseDecl(cppDecl);
    }

    return result;
}

bool DeclVisitor::TraverseDeclContext(clang::DeclContext* context)
{
    bool result = true;
    clang::DeclContext::decl_iterator end = context->decls_end();
    for( clang::DeclContext::decl_iterator iter = context->decls_begin();
         iter != end && result;
         ++iter )
    {
        result = registerDeclaration(*iter);
    }
    return result;
}

bool DeclVisitor::TraverseDecl(clang::Decl * Declaration)
{
    if( !Declaration ) // FIXME sometimes Declaration is null.  I don't know why.
        return true;
    if( Declaration->isTemplateDecl() ) {
       //std::cout << "Skipping templated declaration";
        switch (Declaration->getKind()) {
            case clang::Decl::Function:
            case clang::Decl::Record:
            case clang::Decl::CXXRecord:
            case clang::Decl::CXXMethod:
            case clang::Decl::ClassTemplate:
            case clang::Decl::FunctionTemplate:
                // These ones have names, so we can print them out
                //std::cout << " " << static_cast<clang::NamedDecl*>(Declaration)->getNameAsString();
                break;
            default:
                break;
        }
        //std::cout << ".\n";
    }
    else {
        try {
            RecursiveASTVisitor<DeclVisitor>::TraverseDecl(Declaration);
        }
        catch( cpp::SkipUnwrappableType& e)
        {
            if( decl_in_progress )
            {
                decl_in_progress->markUnwrappable();
            }
            else {
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

bool DeclVisitor::TraverseCXXMethodDecl(clang::CXXMethodDecl* cppDecl)
{
    const clang::CXXRecordDecl * parent_decl = cppDecl->getParent();
    if( hasTemplateParent(parent_decl) )
    {
        decl_in_progress->markUnwrappable();
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

        return result;
    }
    catch( SkipUnwrappableDeclaration& e )
    {
        // If we can't wrap the return type or any of the arguments,
        // then we cannot wrap the method declaration
        decl_in_progress->markUnwrappable();
        return result;
    }
}

bool DeclVisitor::TraverseCXXConstructorDecl(clang::CXXConstructorDecl* cppDecl)
{
    const clang::CXXRecordDecl * parent_decl = cppDecl->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<DeclVisitor>::TraverseCXXConstructorDecl(cppDecl);
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

    return true;
}

bool DeclVisitor::WalkUpFromDecl(clang::Decl* cppDecl)
{
    if( !decl_in_progress )
        throw SkipUnwrappableDeclaration(cppDecl);
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
    return TraverseDeclContext(cppDecl);
}

bool DeclVisitor::TraverseLinkageSpecDecl(clang::LinkageSpecDecl* cppDecl)
{
    return TraverseDeclContext(cppDecl);
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

bool DeclVisitor::TraverseEmptyDecl(clang::EmptyDecl* cppDecl)
{
    allocateDeclaration<clang::Decl, UnwrappableDeclaration>(cppDecl);
    return true;
}

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

bool DeclVisitor::VisitParmVarDecl(clang::ParmVarDecl* cppDecl)
{
    return TraverseType(cppDecl->getType());
}

bool DeclVisitor::WalkUpFromRecordDecl(clang::RecordDecl* cppDecl)
{
    if( cppDecl->isUnion() )
    {
        decl_in_progress = std::make_shared<UnionDeclaration>(cppDecl);
    }
    else if( cppDecl->isStruct() || cppDecl->isClass() )
    {
        decl_in_progress = std::make_shared<RecordDeclaration>(cppDecl);
    }
    else {
        // There's no logic to deal with these; we shouldn't reach here.
        throw SkipUnwrappableDeclaration(cppDecl);
    }

    return Super::WalkUpFromRecordDecl(cppDecl);
}

bool DeclVisitor::VisitFunctionDecl(clang::FunctionDecl* cppDecl)
{
    return TraverseType(cppDecl->getResultType());
}

bool DeclVisitor::VisitTypedefDecl(clang::TypedefDecl* cppDecl)
{
    clang::QualType undertype = cppDecl->getUnderlyingType();
    return TraverseType(undertype);
}

bool DeclVisitor::VisitNamedDecl(clang::NamedDecl* cppDecl)
{
    decl_in_progress->setName(cppDecl->getNameAsString());
    return true;
}
