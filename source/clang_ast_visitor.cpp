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

ASTVisitor::ASTVisitor()
{ }

bool ASTVisitor::TraverseDecl(clang::Decl * Declaration)
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
        RecursiveASTVisitor<ASTVisitor>::TraverseDecl(Declaration);
    }

    return true;
}

bool ASTVisitor::TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration)
{
    std::cout << "Skipping partially specialized template declaration " << declaration->getNameAsString() << ".\n";
    return true;
}

bool ASTVisitor::TraverseClassTemplateSpecializationDecl(clang::ClassTemplateSpecializationDecl* declaration)
{
    std::cout << "Skipping specialized template declaration " << declaration->getNameAsString() << ".\n";
    return true;
}

bool ASTVisitor::TraverseCXXMethodDecl(clang::CXXMethodDecl* Declaration)
{
    const clang::CXXRecordDecl * parent_decl = Declaration->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<ASTVisitor>::TraverseCXXMethodDecl(Declaration);
    }

    return true;
}

bool ASTVisitor::TraverseCXXConstructorDecl(clang::CXXConstructorDecl* Declaration)
{
    const clang::CXXRecordDecl * parent_decl = Declaration->getParent();
    if( !hasTemplateParent(parent_decl) )
    {
        RecursiveASTVisitor<ASTVisitor>::TraverseCXXConstructorDecl(Declaration);
    }

    return true;
}

bool ASTVisitor::VisitFunctionDecl(clang::FunctionDecl * Declaration)
{
    clang::QualType return_type = Declaration->getResultType();

    std::cout << "Found function ";
    printPresumedLocation(Declaration);
    std::cout << "  with return type " << return_type.getAsString() << "\n";
    try {
        Type::get(return_type);

        std::cout << "  argument types:\n";
        for( clang::ParmVarDecl** iter = Declaration->param_begin();
             iter != Declaration->param_end();
             iter++ )
        {
            clang::QualType arg_type = (*iter)->getType();
            std::cout << "\t" << arg_type.getAsString() << "\n";
            Type::get(arg_type);
        }
        functions.insert(Declaration);
    }
    catch( cpp::SkipUnwrappableDeclaration& e)
    {
        std::cout << "WARNING: " << e.what() << "\n";
    }
    return true;
}

bool ASTVisitor::VisitTypedefDecl(clang::TypedefDecl * decl)
{
    //assert(output_type == nullptr);
    std::cout << "name = " << decl->getNameAsString() << "\n";
    Super::VisitTypedefDecl(decl);


    return true;
}

