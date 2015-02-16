/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014-2015 Paul O'Neil <redballoon36@gmail.com>
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

#include <algorithm>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>

#include "clang/Frontend/ASTUnit.h"

#include "configuration.hpp"
#include "cpp_decl.hpp"

static clang::DeclContextLookupResult lookupDeclName(const binder::string& binder_name, clang::ASTContext& ast, clang::DeclContext* context)
{
    std::string name(binder_name.c_str());
    std::string top_name;
    auto scope_start = std::adjacent_find(begin(name), end(name), [](char a, char b) {
                if( a != ':' ) return false;
                return a == b;
                });
    top_name = std::string(begin(name), scope_start);

    clang::IdentifierInfo& id_info = ast.Idents.get(top_name);
    clang::DeclarationName decl_name = ast.DeclarationNames.getIdentifier(&id_info);

    clang::DeclContextLookupResult result = context->lookup(decl_name);
    if( scope_start == end(name) )
    {
        return result;
    }
    else
    {
        std::string remaining_name = std::string(scope_start + 2, end(name));
        if( result.size() == 0 )
        {
            throw std::runtime_error("Looking for a decl contained by another decl, but the outer decl does not contain the inner decl.");
        }
        else if( result.size() > 1 )
        {
            throw std::runtime_error("Looking for a nested decl, but found many decls at one step on the path.");
        }
        else {
            clang::NamedDecl * decl = result.front();
            clang::DeclContext * next_context = clang::Decl::castToDeclContext(decl);
            return lookupDeclName(binder::string(remaining_name.c_str()), ast, next_context);
        }
    }
}
static clang::DeclContextLookupResult lookupDeclName(const binder::string* binder_name, clang::ASTContext& ast, clang::DeclContext* context)
{
    return lookupDeclName(*binder_name, ast, context);
}

void applyConfigToObject(const binder::string* name, clang::ASTUnit* astunit, const DeclarationAttributes* decl_attributes, const TypeAttributes* type_attributes)
{
    clang::ASTContext& ast = astunit->getASTContext();
    // Find the thing to add decl_attributes
    clang::DeclContextLookupResult lookup_result = lookupDeclName(name, ast, ast.getTranslationUnitDecl());
    if( lookup_result.size() > 0 )
    {
        // TODO finding more than one match should probably
        // be handled more gracefully.
        for( clang::NamedDecl* cppDecl : lookup_result )
        {
            Declaration* decl;
            try {
                decl = getDeclaration(cppDecl);
            }
            catch( std::out_of_range& exc )
            {
                std::cerr << "Could not find declaration for " << name << "\n";
                continue;
            }
            if (decl == nullptr)
            {
                std::cerr << "Could not find declaration for " << name << "\n";
                continue;
            }

            decl->applyAttributes(decl_attributes);
            try {
                if (decl->isWrappable() && decl->getType() != nullptr)
                {
                    decl->getType()->applyAttributes(type_attributes);
                }
            }
            catch (NotTypeDecl&)
            {
                // If the decl is not a type decl, then we don't apply type
                // attributes to it, so nothing to do here.
            }
        }
    }
    else {
        Type::range_t search_result = Type::getByName(name);

        if( search_result.first == search_result.second )
        {
            // FIXME better error handling with stuff like localization
            std::cerr << "WARNING: type " << name->c_str() << " does not appear in the C++ source.\n";
            return;
        }

        for (Type * type = search_result.first->second;
                search_result.first != search_result.second;
                type = (++search_result.first)->second)
        {
            type->applyAttributes(type_attributes);
        }
    }

}
