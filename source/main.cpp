/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014 Paul O'Neil <redballoon36@gmail.com>
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#include <memory>

#include "clang/AST/ASTConsumer.h"
#include "clang/AST/ASTContext.h"
#include "clang/AST/RecursiveASTVisitor.h"
#include "clang/Frontend/ASTUnit.h"
#include "clang/Frontend/CompilerInstance.h"
#include "clang/Frontend/FrontendAction.h"
#include "clang/Tooling/Tooling.h"

#include "cli.hpp"
#include "cpp_type.hpp"
#include "cpp_decl.hpp"
#include "configuration.hpp"
#include "dlang_decls.hpp"
#include "dlang_output.hpp"

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
    std::cout << "There are " << cpp::DeclVisitor::getFreeDeclarations().size() << " top level decarations.\n";

    populateDAST();
    // TODO force translation of all types

    //DOutput output;
    produceOutputForPackage(*dlang::rootPackage);

    //funcVisitor.outputTranslatedFunctionDeclarations(output);

    return EXIT_SUCCESS;
}
