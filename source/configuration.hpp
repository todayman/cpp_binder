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
std::vector<std::string> parseClangArgs(const std::vector<std::string>& config_files);
void parseAndApplyConfiguration(const std::vector<std::string>& config_files, clang::ASTContext& ast);

#endif // __CONFIGURATION_HPP__
