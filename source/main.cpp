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
#include "cpp_decl.hpp"
#include "configuration.hpp"

const clang::SourceManager * source_manager = nullptr;

int main(int argc, const char **argv)
{
    CLIArguments args;
    if( !parse_args(argc, argv, args) )
        return EXIT_FAILURE;

    std::string contents = readFile(args.header_files[0]);
    std::vector<std::string> clang_args;
    clang_args.emplace_back("-std=c++11");
    clang_args.emplace_back("-resource-dir");
    clang_args.emplace_back("/usr/lib/clang/3.4.2");

    std::shared_ptr<clang::ASTUnit> ast(clang::tooling::buildASTFromCodeWithArgs(contents, clang_args, args.header_files[0]));
    source_manager = &ast->getSourceManager();

    cpp::DeclVisitor declVisitor(&ast->getASTContext().getPrintingPolicy());

    declVisitor.TraverseDecl(ast->getASTContext().getTranslationUnitDecl());

    cpp::DeclVisitor::enableDeclarationsInFiles(args.header_files);

    try {
        parseAndApplyConfiguration(args.config_files, ast->getASTContext());
    }
    catch(ConfigurationException& exc)
    {
        std::cerr << "ERROR: " << exc.what() << "\n";
        return EXIT_FAILURE;
    }

    std::cout << "\n\n";
    for( auto decl : cpp::DeclVisitor::getFreeDeclarations() )
    {
        std::cerr << "- ";
        decl->decl()->dump();
        std::cerr << "\n";
    }
    std::cout << "There are " << cpp::DeclVisitor::getFreeDeclarations().size() << " top level decarations.\n";
    // TODO force translation of all types

    //DOutput output;

    //funcVisitor.outputTranslatedFunctionDeclarations(output);

    return EXIT_SUCCESS;
}
