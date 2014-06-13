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
        output.putItem("extern(C++)");
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

        output.semicolon();
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

struct CLIArguments
{
    std::vector<std::string> config_files;
    std::vector<std::string> header_files;
    std::string output_dir;
};

bool parse_args(int argc, const char** argv, CLIArguments& args)
{
    bool setOutput = false;
    for( int cur_arg_idx = 1; cur_arg_idx < argc; ++cur_arg_idx )
    {
        std::string arg_str(argv[cur_arg_idx]);
        if( arg_str == "--config-file" || arg_str == "-c" )
        {
            cur_arg_idx += 1;
            if( cur_arg_idx == argc ) {
                std::cout << "Expected path to configuration file after " << arg_str << "\n";
                return false;
            }
            args.config_files.emplace_back(argv[cur_arg_idx]);
        }
        else if( arg_str == "--output" || arg_str == "-o" )
        {
            if( setOutput ) {
                std::cout << "Only one output directory may be specified.\n";
                return false;
            }

            cur_arg_idx += 1;
            if( cur_arg_idx == argc ) {
                std::cout << "Expected path to output directory after " << arg_str << "\n";
                return false;
            }
            args.output_dir = argv[cur_arg_idx];
            setOutput = true;
        }
        else {
            // TODO should I be using emplace_back here instead of push_back?
            args.header_files.emplace_back(arg_str);
        }
    }
    return true;
}

int main(int argc, const char **argv)
{
    CLIArguments args;
    if( !parse_args(argc, argv, args) )
        return EXIT_FAILURE;

    std::string contents = readFile(argv[1]);
    std::vector<std::string> clang_args;
    std::shared_ptr<clang::ASTUnit> ast(clang::tooling::buildASTFromCodeWithArgs(contents, clang_args, argv[1]));

    FunctionVisitor funcVisitor;

    funcVisitor.TraverseDecl(ast->getASTContext().getTranslationUnitDecl());

    // TODO force translation of all types

    DOutput output;

    funcVisitor.outputTranslatedFunctionDeclarations(output);
}
