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

import core.exception : RangeError;
import std.stdio : stdout;

import std.d.ast;
import std.d.lexer;

class Package
{
    public:
    Module[IdentifierChain] children;

    Module getOrCreateModulePath(string path)
    {
        IdentifierChain idChain = makeIdentifierChain(path);
        try {
            return children[idChain];
        }
        catch (RangeError)
        {
            Module mod = new Module();
            ModuleDeclaration decl = new ModuleDeclaration();
            mod.moduleDeclaration = decl;

            decl.moduleName = idChain;
            children[idChain] = mod;

            return mod;
        }
    }
}

Package rootPackage;

IdentifierChain makeIdentifierChain(string path)
{
    import std.algorithm : map, filter, splitter;
    import std.array : array;

    auto result = new IdentifierChain();
    result.identifiers =
      path.splitter('.')
        .filter!(a => a.length != 0)
        .map!(a => Token(tok!"identifier", a, 0, 0, 0))
        .array;
    return result;
}
static this()
{
    rootPackage = new Package();
}
