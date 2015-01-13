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

#include <algorithm>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>

#include "yajl/yajl_tree.h"

#include "configuration.hpp"
#include "cpp_decl.hpp"

class ExpectedObject : ConfigurationException
{
    public:
    // TODO incorporate the value (with context)
    // into the error message.
    ExpectedObject(std::shared_ptr<yajl_val_s>)
        : ConfigurationException("Expected JSON object, got something like number, array, etc.")
    { }
    ExpectedObject(const yajl_val_s*)
        : ConfigurationException("Expected JSON object, got something like number, array, etc.")
    { }
};

// TODO make this a template, class for each type
class ExpectedString : ConfigurationException
{
    public:
    // TODO incorporate the value (with context)
    // into the error message.
    ExpectedString(const yajl_val_s*)
        : ConfigurationException("Expected JSON string, got something like number, array, etc.")
    { }
};

class ExpectedInteger : ConfigurationException
{
    public:
    // TODO incorporate the value (with context)
    // into the error message.
    ExpectedInteger(const yajl_val_s*)
        : ConfigurationException("Expected JSON integer, got something like object, array, etc.")
    { }
};

class ExpectedArray : ConfigurationException
{
    public:
    // TODO incorporate the value (with context)
    // into the error message.
    ExpectedArray(const yajl_val_s*)
        : ConfigurationException("Expected JSON array, got something like object, number, etc.")
    { }
};

class UnknownVisibility : ConfigurationException
{
    public:
    // TODO add context
    UnknownVisibility(const std::string& str)
        : ConfigurationException("Unknown visibility \"" + str + "\".")
    { }
};

class ExpectedNObjects : ConfigurationException
{
    std::string msg;

    public:
    // TODO add context
    ExpectedNObjects(const yajl_val_s& container, size_t expected_count)
        : ConfigurationException("Dummy")
    {
        std::ostringstream strm;
        strm << "Expected an object with " << expected_count << " elements, but found " << container.u.object.len << " instead.";
        msg = strm.str();
    }

    virtual const char * what() const noexcept override
    {
        return msg.c_str();
    }
};

struct ExpectedDDecl : ConfigurationException
{
    ExpectedDDecl(const yajl_val_s&)
        : ConfigurationException("Expected a \"d_decl\" entry for the replace translation strategy.")
    { }
};

struct UnrecognizedAttribute : ConfigurationException
{
    UnrecognizedAttribute(const std::string& attrib)
        : ConfigurationException(std::string("Unrecognized attribute \"") + attrib + ".")
    { }
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

static void applyRootObjectForAttributes(const yajl_val_s& obj, clang::ASTContext& ast);
static void applyConfigToObjectMap(const yajl_val_s& obj_container, clang::ASTContext& ast);
static void applyConfigToObject(const std::string& name, const yajl_val_s& obj, clang::ASTContext& ast);
static void readStrategyConfiguration(const yajl_val_s& container, Type* type);

static std::shared_ptr<yajl_val_s> parseJSON(const std::string& filename)
{
    std::string config_contents = readFile(filename);
    constexpr size_t BUFFER_SIZE = 512;
    char error_buffer[BUFFER_SIZE];

    yajl_val tree_root_raw = yajl_tree_parse(config_contents.c_str(), error_buffer, BUFFER_SIZE);
    if( !tree_root_raw )
    {
        error_buffer[BUFFER_SIZE - 1] = 0; // FIXME I don't know if I need that
        throw ConfigurationException(error_buffer);
    }
    std::shared_ptr<yajl_val_s> tree_root(tree_root_raw, yajl_tree_free);

    if( !YAJL_IS_OBJECT(tree_root) )
    {
        throw ExpectedObject(tree_root);
    }

    return tree_root;
}

static void applyConfigFromFile(const std::string& filename, clang::ASTContext& ast)
{
    std::shared_ptr<yajl_val_s> tree_root = parseJSON(filename);
    applyRootObjectForAttributes(*tree_root.get(), ast);
}

static void applyRootObjectForAttributes(const yajl_val_s& obj, clang::ASTContext& ast)
{
    for( size_t idx = 0; idx < obj.u.object.len; ++idx )
    {
        std::string name = obj.u.object.keys[idx];
        const yajl_val_s* sub_obj = obj.u.object.values[idx];
        if( !sub_obj )
        {
            throw 5;
        }

        if( name == "clang_args" )
        {
            continue;
        }
        else if( name == "binding_attributes" )
        {
            if( !YAJL_IS_OBJECT(sub_obj) )
            {
                throw ExpectedObject(sub_obj);
            }
            applyConfigToObjectMap(*sub_obj, ast);
        }
        else {
            throw ConfigurationException(std::string("Unexpected top-level key \"") + name + "\".");
        }
    }
}

static void applyConfigToObjectMap(const yajl_val_s& obj, clang::ASTContext& ast)
{
    for( size_t idx = 0; idx < obj.u.object.len; ++idx )
    {
        std::string name = obj.u.object.keys[idx];
        const yajl_val_s* sub_obj = obj.u.object.values[idx];
        if( !sub_obj )
        {
            throw 5;
        }
        if( !YAJL_IS_OBJECT(sub_obj) )
        {
            throw ExpectedObject(sub_obj);
        }

        applyConfigToObject(name, *sub_obj, ast);
    }
}

clang::DeclContextLookupResult lookupDeclName(const std::string& name, clang::ASTContext& ast, clang::DeclContext* context)
{
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
            return lookupDeclName(remaining_name, ast, next_context);
        }
    }
}

static void applyConfigToObject(const std::string& name, const yajl_val_s& obj, clang::ASTContext& ast)
{
    assert(YAJL_IS_OBJECT(&obj));
    // Find the thing to add attributes
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

            for( size_t idx = 0; idx < obj.u.object.len; ++idx )
            {
                std::string attrib_name = obj.u.object.keys[idx];
                const yajl_val_s* sub_obj = obj.u.object.values[idx];

                // TODO get these string constants out of here
                // TODO change to a hash table of std::function??
                if( attrib_name == "bound" )
                {
                    // FIXME bools might come through as strings
                    if( !YAJL_IS_INTEGER(sub_obj) )
                    {
                        throw ExpectedInteger(sub_obj);
                    }
                    decl->shouldBind(sub_obj->u.number.i);
                }
                else if( attrib_name == "target_module" )
                {
                    if( !YAJL_IS_STRING(sub_obj) )
                    {
                        throw ExpectedString(sub_obj);
                    }
                    string str(sub_obj->u.string);
                    decl->setTargetModule(&str);
                }
                else if( attrib_name == "visibility" )
                {
                    if( !YAJL_IS_STRING(sub_obj) )
                    {
                        throw ExpectedString(sub_obj);
                    }
                    std::string vis_str = sub_obj->u.string;
                    std::for_each(vis_str.begin(), vis_str.end(),
                            [](char& ch) {
                                ch = std::tolower(ch); // FIXME? depends on locale
                                });
                    if( vis_str == "private" )
                    {
                        decl->setVisibility(PRIVATE);
                    }
                    else if( vis_str == "package" )
                    {
                        decl->setVisibility(PACKAGE);
                    }
                    else if( vis_str == "protected" )
                    {
                        decl->setVisibility(PROTECTED);
                    }
                    else if( vis_str == "public" )
                    {
                        decl->setVisibility(PUBLIC);
                    }
                    else if( vis_str == "export" )
                    {
                        decl->setVisibility(EXPORT);
                    }
                    else {
                        throw UnknownVisibility(vis_str);
                    }
                }
                else if( attrib_name == "remove_prefix")
                {
                    if( !YAJL_IS_STRING(sub_obj) )
                    {
                        throw ExpectedString(sub_obj);
                    }
                    string str(sub_obj->u.string);
                    decl->removePrefix(&str);
                }
                else if( attrib_name == "strategy" )
                {
                    if( !YAJL_IS_OBJECT(sub_obj) )
                    {
                        throw ExpectedObject(sub_obj);
                    }
                    if( decl->isWrappable() ) // FIXME apply this higher up?
                    {
                        readStrategyConfiguration(*sub_obj, decl->getType());
                    }
                }
                else {
                    // throw UnrecognizedAttribute(attrib_name);
                    // TODO I think I should just log this instead
                    throw UnrecognizedAttribute(attrib_name);
                }
            }
        }
    }
    else {
        string str(name.c_str());
        Type* type = Type::getByName(&str);
        if( !type )
        {
            // FIXME better error handling with stuff like localization
            std::cerr << "WARNING: type " << name << " does not appear in the C++ source.\n";
            return;
        }

        for( size_t idx = 0; idx < obj.u.object.len; ++idx )
        {
            std::string attrib_name = obj.u.object.keys[idx];
            const yajl_val_s* sub_obj = obj.u.object.values[idx];
            if( attrib_name == "strategy" )
            {
                if( !YAJL_IS_OBJECT(sub_obj) )
                {
                    throw ExpectedObject(sub_obj);
                }
                readStrategyConfiguration(*sub_obj, type);
            }
            else {
                // throw UnrecognizedAttribute(attrib_name);
                // TODO I think I should just log this instead
                throw UnrecognizedAttribute(attrib_name);
            }
        }
    }

}

static void readStrategyConfiguration(const yajl_val_s& container, Type* type)
{
    for( size_t idx = 0; idx < container.u.object.len; ++idx )
    {
        if( std::string("name") == container.u.object.keys[idx] )
        {
            yajl_val name_obj = container.u.object.values[idx];
            if( !YAJL_IS_STRING(name_obj) )
            {
                throw ExpectedString(name_obj);
            }

            std::string name_str(name_obj->u.string);
            if( name_str == "replace" )
            {
                if( container.u.object.len != 2 )
                {
                    throw ExpectedNObjects(container, 2);
                }

                if( std::string("d_decl") != container.u.object.keys[1 - idx] )
                {
                    throw ExpectedDDecl(container);
                }
                const yajl_val target_obj = container.u.object.values[1 - idx];
                if( !YAJL_IS_STRING(target_obj) )
                {
                    throw ExpectedString(target_obj);
                }
                string str(target_obj->u.string);
                type->chooseReplaceStrategy(&str);
            }
            else if( name_str == "struct" )
            {
                type->setStrategy(STRUCT);
            }
            else if( name_str == "interface" )
            {
                type->setStrategy(INTERFACE);
            }
            else if( name_str == "class" )
            {
                type->setStrategy(CLASS);
            }
            else if( name_str == "opaque_class" )
            {
                type->setStrategy(OPAQUE_CLASS);
            }
        }
    }
}

void parseAndApplyConfiguration(const std::vector<std::string>& config_files, clang::ASTUnit* astunit)
{
    clang::ASTContext& ast = astunit->getASTContext();
    for( const std::string& filename : config_files )
    {
        applyConfigFromFile(filename, ast);
    }
}

void parseAndApplyConfiguration(size_t config_count, const char** config_files, clang::ASTUnit* astunit)
{
    std::vector<std::string> config_file_vec;
    for (size_t i = 0; i < config_count; ++i)
    {
        config_file_vec.push_back(config_files[i]);
    }

    parseAndApplyConfiguration(config_file_vec, astunit);
}
