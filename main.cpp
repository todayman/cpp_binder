#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Frontend/ASTUnit.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Tooling/Tooling.h"

#include <fstream>
#include <iostream>
#include <memory>

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

std::string readFile(const std::string& filename)
{
    std::ifstream input(filename.c_str());
    size_t length;
    input.seekg(0, std::ios::end);
    length = input.tellg();
    input.seekg(0, std::ios::beg);
    std::string result;
    result.resize(length);
    input.read(&result[0], length);
    return result;
}

int main(int argc, const char **argv)
{
    if( argc > 1 )
    {
        std::string contents = readFile(argv[1]);
        std::vector<std::string> clang_args;
        std::shared_ptr<ASTUnit> ast(clang::tooling::buildASTFromCodeWithArgs(contents, clang_args, argv[1]));
        FindNamedClassConsumer consumer(&ast->getASTContext());
        consumer.HandleTranslationUnit(ast->getASTContext());
    }
}
