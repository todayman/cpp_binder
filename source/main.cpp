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
#include <sstream>

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

    std::vector<std::string> clang_args;
    try {
        clang_args = parseClangArgs(args.config_files);
    }
    catch(ConfigurationException& exc)
    {
        std::cerr << "ERROR: " << exc.what() << "\n";
        return EXIT_FAILURE;
    }

    //std::string contents = readFile(args.header_files[0]);
    std::string contents;
    std::ostringstream strm;
    for( const std::string& filename : args.header_files )
    {
        strm << "#include \"" << filename << "\"\n";
    }
    contents = strm.str();

    // FIXME potential collisions with cpp_binder.cpp will really confuse clang
    // If you pass a header here and the source #includes that header,
    // then clang recurses infinitely
    std::unique_ptr<clang::ASTUnit> ast(clang::tooling::buildASTFromCodeWithArgs(contents, clang_args, "cpp_binder.cpp"));
    source_manager = &ast->getSourceManager();

    DeclVisitor declVisitor(&ast->getASTContext().getPrintingPolicy());

    declVisitor.TraverseDecl(ast->getASTContext().getTranslationUnitDecl());

    std::vector<const char*> raw_files;
    raw_files.reserve(args.header_files.size());
    for( auto& str : args.header_files )
    {
        raw_files.push_back(str.c_str());
    }
    enableDeclarationsInFiles(raw_files.size(), raw_files.data());

    try {
        parseAndApplyConfiguration(args.config_files, ast->getASTContext());
    }
    catch(ConfigurationException& exc)
    {
        std::cerr << "ERROR: " << exc.what() << "\n";
        return EXIT_FAILURE;
    }

    try {
        populateDAST();
    }
    catch(std::exception& exc)
    {
        std::cerr << "ERROR: " << exc.what() << "\n";
        return EXIT_FAILURE;
    }

    produceOutputForPackage(*dlang::rootPackage);

    return EXIT_SUCCESS;
}
