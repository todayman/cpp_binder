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

#include "DOutput.hpp"
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
        WrappedType::get(return_type.getTypePtrOrNull());
        functions.insert(Declaration);

        std::cout << "Function has arguments with types: \n";
        for( clang::ParmVarDecl** iter = Declaration->param_begin();
             iter != Declaration->param_end();
             iter++ )
        {
            clang::QualType arg_type = (*iter)->getType();
            std::cout << "\t" << arg_type.getAsString() << "\n";
            WrappedType::get(arg_type.getTypePtrOrNull());
        }
        return true;
    }

    void outputTranslatedFunctionDeclarations(DOutput& output)
    {
        for( const clang::FunctionDecl* cur_func : functions )
        {
            translateFunction(cur_func, output);
        }
    }

    void translateFunction(const clang::FunctionDecl* cur_func, DOutput& output)
    {
        // TODO deal with qualifiers
        clang::QualType qualified_return_type = cur_func->getResultType();
        const WrappedType * return_type = WrappedType::get(qualified_return_type.getTypePtrOrNull());
        return_type->translate(output);
        output.putItem(cur_func->getName().str());

        output.beginList();
        for( clang::ParmVarDecl* const * iter = cur_func->param_begin();
             iter != cur_func->param_end();
             iter++ )
        {
            const clang::ParmVarDecl * arg = (*iter);
            clang::QualType qualified_arg_type = arg->getType();
            const WrappedType * arg_type = WrappedType::get(qualified_arg_type.getTypePtrOrNull());

            output.listItem();
            arg_type->translate(output);
            output.putItem(arg->getName().str());
        }

        output.endList();

        output.newline();
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

    // TODO force translation of all types

    DOutput output;

    funcVisitor.outputTranslatedFunctionDeclarations(output);
}
