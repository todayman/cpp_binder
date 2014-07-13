#include <iostream>
#include <set>

#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Basic/SourceManager.h"

#include "cpp_type.hpp"
#include "clang_ast_visitor.hpp"

using namespace cpp;

void printPresumedLocation(const clang::NamedDecl* Declaration)
{
    clang::SourceLocation source_loc = Declaration->getLocation();
    clang::PresumedLoc presumed = source_manager->getPresumedLoc(source_loc);

    std::cout << Declaration->getNameAsString() << " at " << presumed.getFilename() << ":" << presumed.getLine() << "\n";
}

bool FunctionVisitor::TraverseDecl(clang::Decl * Declaration)
{
    if( !Declaration ) // FIXME sometimes Declaration is null.  I don't know why.
        return true;
    if( Declaration->isTemplateDecl() ) {
       std::cout << "Skipping templated declaration";
        switch (Declaration->getKind()) {
            case clang::Decl::Function:
            case clang::Decl::Record:
            case clang::Decl::CXXRecord:
            case clang::Decl::CXXMethod:
            case clang::Decl::ClassTemplate:
            case clang::Decl::FunctionTemplate:
                // These ones have names, so we can print them out
                std::cout << " " << static_cast<clang::NamedDecl*>(Declaration)->getNameAsString();
                break;
            default:
                break;
        }
        std::cout << ". \n";
    }
    else {
        RecursiveASTVisitor<FunctionVisitor>::TraverseDecl(Declaration);
    }

    return true;
}

bool FunctionVisitor::TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration)
{
    std::cout << "Skipping partially specialized template declaration " << declaration->getNameAsString() << ".\n";
    return true;
}

bool FunctionVisitor::TraverseClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* declaration)
{
    std::cout << "Skipping specialized template declaration " << declaration->getNameAsString() << ".\n";
    return true;
}

bool FunctionVisitor::TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration)
{
    const clang::CXXRecordDecl * parent_decl = Declaration->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<FunctionVisitor>::TraverseCXXMethodDecl(Declaration);
    }

    return true;
}

bool FunctionVisitor::TraverseCXXConstructorDecl(clang::CXXConstructorDecl* Declaration)
{
    const clang::CXXRecordDecl * parent_decl = Declaration->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<FunctionVisitor>::TraverseCXXConstructorDecl(Declaration);
    }

    return true;
}

bool FunctionVisitor::VisitFunctionDecl(clang::FunctionDecl * Declaration)
{
    clang::QualType return_type = Declaration->getResultType();

    std::cout << "Found function ";
    printPresumedLocation(Declaration);
    std::cout << "  with return type " << return_type.getAsString() << "\n";
    try {
        // TODO could this really be NULL?
        // under what circumstances is that the case, and do I have to
        // worry about it?
        cpp::Type::get(return_type.getTypePtrOrNull());

        std::cout << "  argument types:\n";
        for( clang::ParmVarDecl** iter = Declaration->param_begin();
             iter != Declaration->param_end();
             iter++ )
        {
            clang::QualType arg_type = (*iter)->getType();
            std::cout << "\t" << arg_type.getAsString() << "\n";
            cpp::Type::get(arg_type.getTypePtrOrNull());
        }
        functions.insert(Declaration);
    }
    catch( cpp::SkipUnwrappableDeclaration& e)
    {
        std::cout << "WARNING: " << e.what() << "\n";
    }
    return true;
}
