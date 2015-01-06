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

import core.exception : RangeError;

import std.algorithm : map, filter, splitter;
import std.array : array;
import std.stdio : stdout;

import std.d.ast;
import std.d.lexer;

class Package
{
    public:
    // TODO make sure that IdentifierChain hashes the right way
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
    auto result = new IdentifierChain();
    result.identifiers =
      path.splitter('.')
        .filter!(a => a.length != 0)
        .map!(a => Token(tok!"identifier", a, 0, 0, 0))
        .array;
    return result;
}

IdentifierOrTemplateInstance makeInstance(string str)
{
    auto result = new IdentifierOrTemplateInstance();
    result.identifier = Token(tok!"identifier", str, 0, 0, 0);
    return result;
}
IdentifierOrTemplateInstance makeInstance(Token t)
{
    auto result = new IdentifierOrTemplateInstance();
    result.identifier = t;
    return result;
}

// FIXME combine this with makeIdentifierChain
IdentifierOrTemplateChain makeIdentifierOrTemplateChain(string path)
{
    import std.algorithm : map, filter, splitter;
    import std.array : array;

    auto result = new IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances =
      path.splitter('.')
        .filter!(a => a.length != 0)
        .map!(makeInstance)
        .array;
    return result;
}

IdentifierOrTemplateChain concatIdTemplateChain(IdentifierChain idChain, IdentifierOrTemplateChain tempChain)
{
    auto result = new IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances = idChain.identifiers.map!(makeInstance).array ~ tempChain.identifiersOrTemplateInstances;
    return result;
}

void append(IdentifierOrTemplateChain chain, Token identifier)
{
    //auto t = Token(tok!"identifier", identifier, 0, 0, 0);
    auto instance = new IdentifierOrTemplateInstance();
    instance.identifier = identifier;
    chain.identifiersOrTemplateInstances ~= [instance];
}

static this()
{
    rootPackage = new Package();
}
