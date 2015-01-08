/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2015 Paul O'Neil <redballoon36@gmail.com>
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

#include <string>
#include <vector>

#include "clang/Frontend/ASTUnit.h"
#include "clang/Tooling/Tooling.h"

#include "clang_wrapper.hpp"

clang::ASTUnit* buildAST(char * contents, size_t arg_len, char** raw_args, char * filename)
{
    std::vector<std::string> clang_args;
    clang_args.resize(arg_len);
    for (size_t i = 0; i < arg_len; ++i)
    {
        clang_args.at(i) = raw_args[i];
    }
    return clang::tooling::buildASTFromCodeWithArgs(contents, clang_args, filename).release();
}
