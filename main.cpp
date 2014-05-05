#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Tooling/Tooling.h"

using namespace clang;

class FindNamedClassVisitor : public RecursiveASTVisitor<FindNamedClassVisitor>
{
    public:
    explicit FindNamedClassVisitor(ASTContext * Context)
        : Context(Context)
    { }

    bool VisitCXXRecordDecl(CXXRecordDecl * Declaration)
    {
        if( Declaration->getQualifiedNameAsString() == "n::m::C" )
        {
            FullSourceLoc FullLocation = Context->getFullLoc(Declaration->getLocStart());
            if( FullLocation.isValid() )
            {
                llvm::outs() << "Found declaration at "
                    << FullLocation.getSpellingLineNumber() << ":"
                    << FullLocation.getSpellingColumnNumber() << "\n";
            }
        }
        return true;
    }

    private:
    ASTContext * Context;
};

class FindNamedClassConsumer : public ASTConsumer
{
    public:
    explicit FindNamedClassConsumer(ASTContext * Context)
        : Visitor(Context)
    { }

    virtual void HandleTranslationUnit(ASTContext &Context)
    {
        Visitor.TraverseDecl(Context.getTranslationUnitDecl());
    }

    private:
    FindNamedClassVisitor Visitor;
};

class FindNamedClassAction : public clang::ASTFrontendAction
{
    public:
    virtual ASTConsumer * CreateASTConsumer(CompilerInstance& Compiler, llvm::StringRef)
    {
        return new FindNamedClassConsumer(&Compiler.getASTContext());
    }
};

int main(int argc, const char **argv)
{
    if( argc > 1 )
    {
        clang::tooling::runToolOnCode(new FindNamedClassAction, argv[1]);
    }
}
