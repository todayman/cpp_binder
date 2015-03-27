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

import std.algorithm : map, filter, splitter;
import std.array : array;
import std.stdio : stdout;

import std.d.ast;
import std.d.lexer;

class Package
{
    public:
    Module[string] children;

    Module getOrCreateModulePath(string path)
    {
        if (auto ptr = path in children)
        {
            return *ptr;
        }
        else
        {
            Module mod = new Module();
            ModuleDeclaration decl = new ModuleDeclaration();
            mod.moduleDeclaration = decl;

            decl.moduleName = makeIdentifierChain(path);
            children[path] = mod;

            return mod;
        }
    }
}

Package rootPackage;

IdentifierChain makeIdentifierChain(string separator = ".")(string path)
{
    auto result = new IdentifierChain();
    result.identifiers =
      path.splitter(separator)
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

IdentifierOrTemplateChain makeIdentifierOrTemplateChain(IdentifierOrTemplateInstance inst)
{
    auto result = new IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances = [inst];
    return result;
}

IdentifierOrTemplateChain makeIdentifierOrTemplateChain(IdentifierChain idChain)
{
    auto result = new IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances = idChain.identifiers.map!(makeInstance).array;
    return result;
}

// FIXME combine this with makeIdentifierChain
IdentifierOrTemplateChain makeIdentifierOrTemplateChain(string separator)(string path)
{
    import std.algorithm : map, filter, splitter;
    import std.array : array;

    auto result = new IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances =
      path.splitter(separator)
        .filter!(a => a.length != 0)
        .map!(makeInstance)
        .array;
    return result;
}

IdentifierOrTemplateChain concat(IdentifierChain idChain, IdentifierOrTemplateChain tempChain)
{
    auto result = new IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances = idChain.identifiers.map!(makeInstance).array ~ tempChain.identifiersOrTemplateInstances;
    return result;
}
IdentifierOrTemplateChain concat(IdentifierOrTemplateChain idChain, IdentifierOrTemplateChain tempChain)
{
    auto result = new IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances = idChain.identifiersOrTemplateInstances ~ tempChain.identifiersOrTemplateInstances;
    return result;
}

void append(IdentifierOrTemplateChain chain, Token identifier)
{
    //auto t = Token(tok!"identifier", identifier, 0, 0, 0);
    auto instance = new IdentifierOrTemplateInstance();
    instance.identifier = identifier;
    chain.identifiersOrTemplateInstances ~= [instance];
}

void stripExternCpp(std.d.ast.Declaration decl)
{
    foreach (uint idx, attr; decl.attributes)
    {
        if (attr.linkageAttribute !is null)
        {
            std.d.ast.LinkageAttribute linkage = attr.linkageAttribute;
            // FIXME for some reason, just comparing
            // linkage.identifier != Token(tok!"identifier", "C", 0, 0, 0)
            // caused a compiler error
            if (linkage.identifier.type != tok!"identifier"
              || linkage.identifier.text != "C"
              || linkage.hasPlusPlus == false)
            {
                continue;
            }

            decl.attributes = decl.attributes[0 .. idx] ~ decl.attributes[idx+1 .. $];
            break;
        }
    }
}

class ModuleWithNamespaces
{
    protected:
    std.d.ast.Module mod;
    std.d.ast.Declaration[string] namespaces;

    public:
    this(string path)
    {
        mod = new std.d.ast.Module();
        mod.moduleDeclaration = new std.d.ast.ModuleDeclaration();
        mod.moduleDeclaration.moduleName = makeIdentifierChain(path);
    }

    void addDeclaration(std.d.ast.Declaration decl, string namespace)
    {
        if (namespace == "")
        {
            mod.declarations ~= [decl];
            return;
        }

        if (auto dest = namespace in namespaces)
        {
            dest.declarations ~= [decl];
        }
        else {
            import std.exception : assumeUnique;
            import std.array : appender;
            immutable(string[]) namespace_chain = namespace.splitter("::").filter!(a => a.length != 0).array.assumeUnique;
            auto accumulated_name = appender!string();

            std.d.ast.Declaration parent_namespace = null;
            foreach (ns; namespace_chain)
            {
                string parent_name = accumulated_name.data[];
                accumulated_name.put("::");
                accumulated_name.put(ns);
                string current_name = accumulated_name.data[];

                if (auto nsptr = current_name in namespaces)
                {
                    parent_namespace = *nsptr;
                }
                else
                {
                    auto linkage = new std.d.ast.LinkageAttribute();
                    linkage.identifier = Token(tok!"identifier", "C", 0, 0, 0);
                    linkage.hasPlusPlus = true;
                    linkage.identifierChain = makeIdentifierChain!"::"(ns);

                    auto attr = new std.d.ast.Attribute();
                    attr.linkageAttribute = linkage;

                    auto next_namespace = new std.d.ast.Declaration();
                    namespaces[current_name] = next_namespace;
                    next_namespace.attributes ~= [attr];

                    // FIXME I'm not a huge fan of conditions that only apply
                    // once at the beginning inside of loops
                    if (parent_namespace is null)
                    {
                        mod.declarations ~= [next_namespace];
                    }
                    else
                    {
                        parent_namespace.declarations ~= [next_namespace];
                    }
                    parent_namespace = next_namespace;
                }
            }

            parent_namespace.declarations ~= [decl];
        }
        // TODO this isn't really the right place for this, is it?
        stripExternCpp(decl);
    }

    std.d.ast.Module getModule()
    {
        return mod;
    }
}

static this()
{
    rootPackage = new Package();
}
