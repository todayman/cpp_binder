#include <fstream>
#include <iostream>
#include <memory>

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Frontend/ASTUnit.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Tooling/Tooling.h"

#include "WrappedType.hpp"

class FunctionVisitor : public clang::RecursiveASTVisitor<FunctionVisitor>
{
    public:
    std::set<clang::FunctionDecl*> functions;
    bool VisitFunctionDecl(clang::FunctionDecl * Declaration)
    {
        std::cout << "Got here!\n";
        clang::QualType return_type = Declaration->getResultType();
        std::cout << "Found function with return type " << return_type.getAsString() << "\n";
        WrappedType::get(return_type.getTypePtr());
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
    if( argc < 2 )
    {
        return -1;
    }

    std::string contents = readFile(argv[1]);
    std::vector<std::string> clang_args;
    std::shared_ptr<clang::ASTUnit> ast(clang::tooling::buildASTFromCodeWithArgs(contents, clang_args, argv[1]));

    FunctionVisitor funcVisitor;

    funcVisitor.TraverseDecl(ast->getASTContext().getTranslationUnitDecl());
}
