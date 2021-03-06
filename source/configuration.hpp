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

#ifndef __CONFIGURATION_HPP__
#define __CONFIGURATION_HPP__

namespace clang
{
    class ASTUnit;
}

namespace binder
{
    class string;
}

class DeclarationAttributes;
class TypeAttributes;

void applyConfigToObject(const binder::string* name, clang::ASTUnit* astunit, const DeclarationAttributes* decl_attributes, const TypeAttributes* type_attributes);

#endif // __CONFIGURATION_HPP__
