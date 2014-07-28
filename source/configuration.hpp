#ifndef __CONFIGURATION_HPP__
#define __CONFIGURATION_HPP__

#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

#include "clang/Frontend/ASTUnit.h"

class ConfigurationException : public std::runtime_error
{
    public:
    ConfigurationException(std::string msg)
        : std::runtime_error(msg)
    { }
};

std::string readFile(const std::string& filename);
void parseAndApplyConfiguration(const std::vector<std::string>& config_files, clang::ASTContext& ast);

#endif // __CONFIGURATION_HPP__
