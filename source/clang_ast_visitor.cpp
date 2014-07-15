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

void ASTVisitor::maybeInsertType(clang::QualType qType)
{
    // TODO could this really be NULL?
    // under what circumstances is that the case, and do I have to
    // worry about it?
    const clang::Type * cppType = qType.getTypePtr();
    decltype(Type::type_map)::iterator iter = Type::type_map.find(cppType);
    if( iter != Type::type_map.end() ) {
        return;
    }

    TypeVisitor type_visitor;
    type_visitor.TraverseType(qType);
}

bool ASTVisitor::VisitFunctionDecl(clang::FunctionDecl * Declaration)
{
    clang::QualType return_type = Declaration->getResultType();

    std::cout << "Found function ";
    printPresumedLocation(Declaration);
    std::cout << "  with return type " << return_type.getAsString() << "\n";
    try {
        maybeInsertType(return_type);

        std::cout << "  argument types:\n";
        for( clang::ParmVarDecl** iter = Declaration->param_begin();
             iter != Declaration->param_end();
             iter++ )
        {
            clang::QualType arg_type = (*iter)->getType();
            std::cout << "\t" << arg_type.getAsString() << "\n";
            maybeInsertType(arg_type);
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

