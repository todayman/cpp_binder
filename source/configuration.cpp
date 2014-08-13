#include <algorithm>
#include <cstring>
#include <fstream>
#include <iostream>
#include <sstream>

//#include "clang/ASTMatchers/ASTMatchers.h"
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

class UnknownVisiblity : ConfigurationException
{
    public:
    // TODO add context
    UnknownVisiblity(const std::string& str)
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


static void applyConfigToObjectMap(const yajl_val_s& obj_container, clang::ASTContext& ast);
static void applyConfigToObject(const std::string& name, const yajl_val_s& obj, clang::ASTContext& ast);
static void readStrategyConfiguration(const yajl_val_s& container, std::shared_ptr<cpp::Type> type);

static void applyConfigFromFile(const std::string& filename, clang::ASTContext& ast)
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

    applyConfigToObjectMap(*tree_root.get(), ast);
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

static cpp::Declaration* getDecl(clang::Decl*)
{
    return nullptr;
}

static void applyConfigToObject(const std::string& name, const yajl_val_s& obj, clang::ASTContext& ast)
{
    assert(YAJL_IS_OBJECT(&obj));
    // Find the thing to add attributes
    clang::IdentifierInfo& id_info = ast.Idents.get(name);
    clang::DeclarationName decl_name = ast.DeclarationNames.getIdentifier(&id_info);
    clang::DeclContextLookupResult lookup_result = ast.getTranslationUnitDecl()->lookup(decl_name);

    if( lookup_result.size() > 0 )
    {
        // TODO finding more than one match should probably
        // be handled more gracefully.
        for( clang::NamedDecl* cppDecl : lookup_result )
        {
            cpp::Declaration * decl = getDecl(cppDecl);
            //decl->setNameAttribute(name);
            for( size_t idx = 0; idx < obj.u.object.len; ++idx )
            {
                std::string attrib_name = obj.u.object.keys[idx];
                const yajl_val_s* sub_obj = obj.u.object.values[idx];

                // TODO get these string constants out of here
                // TODO change to a hash table of std::function??
                /*if( attrib_name == "name" )
                {
                    if( !YAJL_IS_STRING(sub_obj) )
                    {
                        throw ExpectedString(sub_obj);
                    }
                    // already set the name, but do it again anyway
                    decl->setNameAttribute(sub_obj->u.string);
                }
                else*/ if( attrib_name == "bound" )
                {
                    // FIXME bools might come through as strings
                    if( !YAJL_IS_INTEGER(sub_obj) )
                    {
                        throw ExpectedInteger(sub_obj);
                    }
                    decl->shouldBind(sub_obj->u.number.i);
                }
                else if( attrib_name == "target_module")
                {
                    if( !YAJL_IS_STRING(sub_obj) )
                    {
                        throw ExpectedString(sub_obj);
                    }
                    decl->setTargetModule(sub_obj->u.string);
                }
                else if( attrib_name == "visibility")
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
                        throw UnknownVisiblity(vis_str);
                    }
                }
                else if( attrib_name == "remove_prefix")
                {
                    if( !YAJL_IS_STRING(sub_obj) )
                    {
                        throw ExpectedString(sub_obj);
                    }
                    decl->removePrefix(sub_obj->u.string);
                }
                else if( attrib_name == "strategy" )
                {
                    if( !YAJL_IS_OBJECT(sub_obj) )
                    {
                        throw ExpectedObject(sub_obj);
                    }
                    readStrategyConfiguration(*sub_obj, decl->getType());
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
        std::shared_ptr<cpp::Type> type = cpp::Type::getByName(name);
        if( !type )
        {
            throw 10;
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

static void readStrategyConfiguration(const yajl_val_s& container, std::shared_ptr<cpp::Type> type)
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
                type->chooseReplaceStrategy(target_obj->u.string);
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

void parseAndApplyConfiguration(const std::vector<std::string>& config_files, clang::ASTContext& ast)
{
    for( const std::string& filename : config_files )
    {
        applyConfigFromFile(filename, ast);
    }
}
