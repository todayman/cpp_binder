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

#include "cli.hpp"
#include "DOutput.hpp"
#include "cpp_type.hpp"

const clang::SourceManager * source_manager = nullptr;
using namespace clang;

class FunctionVisitor : public clang::RecursiveASTVisitor<FunctionVisitor>
{
    public:
    std::set<clang::FunctionDecl*> functions;

    bool TraverseDecl(clang::Decl * Declaration)
    {
#define PRINT(X) std::cout << #X << " = " << clang::Decl::X << "\n"
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
                    std::cout << " kind = " << Declaration->getKind();
                    break;
            }
            std::cout << ". \n";
        }
        else {
            //std::cout << "kind = " << Declaration->getKind() << "\n";
            RecursiveASTVisitor<FunctionVisitor>::TraverseDecl(Declaration);
        }

        return true;
    }
    bool TraverseClassTemplatePartialSpecializationDecl(clang::ClassTemplatePartialSpecializationDecl* declaration)
    {
        std::cout << "Skipping partially specialized template declaration " << declaration->getNameAsString() << ".\n";
        return true;
    }

    bool VisitFunctionDecl(clang::FunctionDecl * Declaration)
    {

        clang::QualType return_type = Declaration->getResultType();
        clang::SourceLocation source_loc = Declaration->getLocation();
        clang::PresumedLoc presumed = source_manager->getPresumedLoc(source_loc);

        std::cout << "Found function " << Declaration->getNameAsString() << " at " << presumed.getFilename() << ":" << presumed.getLine() << "\n";
        std::cout << "  with return type " << return_type.getAsString() << "\n";
        // TODO could this really be NULL?
        // under what circumstances is that the case, and do I have to
        // worry about it?
        cpp::Type::get(return_type.getTypePtrOrNull());
        functions.insert(Declaration);

        std::cout << "  argument types:\n";
        for( clang::ParmVarDecl** iter = Declaration->param_begin();
             iter != Declaration->param_end();
             iter++ )
        {
            clang::QualType arg_type = (*iter)->getType();
            std::cout << "\t" << arg_type.getAsString() << "\n";
            cpp::Type::get(arg_type.getTypePtrOrNull());
        }
        return true;
    }

    /*void outputTranslatedFunctionDeclarations(DOutput& output)
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
        const cpp::Type * return_type = cpp::Type::get(qualified_return_type.getTypePtrOrNull());
        return_type->translate(output);
        output.putItem(cur_func->getName().str());

        output.beginList();
        for( clang::ParmVarDecl* const * iter = cur_func->param_begin();
             iter != cur_func->param_end();
             iter++ )
        {
            const clang::ParmVarDecl * arg = (*iter);
            clang::QualType qualified_arg_type = arg->getType();
            const cpp::Type * arg_type = cpp::Type::get(qualified_arg_type.getTypePtrOrNull());

            output.listItem();
            arg_type->translate(output);
            output.putItem(arg->getName().str());
        }

        output.endList();

        output.semicolon();
        output.newline();
    }*/
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
    CLIArguments args;
    if( !parse_args(argc, argv, args) )
        return EXIT_FAILURE;

    std::string contents = readFile(args.header_files[0]);
    std::vector<std::string> clang_args;
    clang_args.emplace_back("-v");
    clang_args.emplace_back("-std=c++11");
    clang_args.emplace_back("-resource-dir");
    clang_args.emplace_back("/usr/lib/clang/3.4.2");

    std::shared_ptr<clang::ASTUnit> ast(clang::tooling::buildASTFromCodeWithArgs(contents, clang_args, args.header_files[0]));
    source_manager = &ast->getSourceManager();

    FunctionVisitor funcVisitor;

    funcVisitor.TraverseDecl(ast->getASTContext().getTranslationUnitDecl());

    // TODO force translation of all types

    //DOutput output;

    //funcVisitor.outputTranslatedFunctionDeclarations(output);
}
