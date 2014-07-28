#include <fstream>
#include <iostream>

#include "yajl/yajl_tree.h"

#include "configuration.hpp"

class ExpectedObject : ConfigurationException
{
    public:
    // TODO incorporate the value (with context)
    // into the error message.
    ExpectedObject(std::shared_ptr<yajl_val_s>)
        : ConfigurationException("Expected JSON object, got something like number, array, etc.")
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
}

void parseAndApplyConfiguration(const std::vector<std::string>& config_files, clang::ASTContext& ast)
{
    for( const std::string& filename : config_files )
    {
        applyConfigFromFile(filename, ast);
    }
}
