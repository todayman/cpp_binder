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
#include <unordered_set>

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

std::unordered_set<const clang::Type*> types;

class FunctionVisitor : public RecursiveASTVisitor<FunctionVisitor>
{
    public:
    std::set<FunctionDecl*> functions;
    bool VisitFunctionDecl(FunctionDecl * Declaration)
    {
        std::cout << "Got here!\n";
        QualType return_type = Declaration->getResultType();
        std::cout << "Found function with return type " << return_type.getAsString() << "\n";
        types.insert(return_type.getTypePtr());
        functions.insert(Declaration);
        return true;
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

        FunctionVisitor funcVisitor;

        funcVisitor.TraverseDecl(ast->getASTContext().getTranslationUnitDecl());
    }
}
