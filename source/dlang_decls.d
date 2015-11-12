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
import std.typecons : Flag, No;

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

            mod.moduleName = makeIdentifierChain(path);
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

// Do I need this?
void stripExternCpp(Declaration decl)
{
    // TODO fill in
}

class ModuleWithNamespaces
{
    protected:
    Module mod;
    Namespace[string] namespaces;

    public:
    this(string path)
    {
        mod = new Module();
        mod.moduleName = makeIdentifierChain(path);
    }

    void addDeclaration(Declaration decl, string namespace)
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

            Namespace parent_namespace = null;
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
                    auto next_namespace = new Namespace();
                    namespaces[current_name] = next_namespace;

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

    Module getModule()
    {
        return mod;
    }
}

class Module
{
    IdentifierChain moduleName;

    Declaration[] declarations;
}

class Namespace : Declaration
{
    Declaration[] declarations;
}

static this()
{
    rootPackage = new Package();
}

enum Visibility
{
    Public,
    Private,
    Protected,
    Export,
    Package,
}

interface Type
{
}

class ReturnType
{
}

class Declaration
{
    Declaration parent;
    // Do all declarations have visibility?
    Visibility visibility;

    string name;
}

class VariableDeclaration : Declaration
{
    Type type;
    // modifiers
    bool extern_;
    bool static_;
    LinkageAttribute linkage; // language linkage
}

class FieldDeclaration : Declaration
{
    Type type;
}

class LinkageAttribute
{
}

class CLinkageAttribute : LinkageAttribute
{
}

// Maybe this should be a struct?
class CppLinkageAttribute : LinkageAttribute
{
    string[] namespacePath;

    this()
    {
        // TODO
    }
    this(string np)
    {
        // TODO
        namespacePath = [];
    }
}

class Argument : Declaration
{
    Type type;
    Flag!"ref_" ref_;
}

class FunctionDeclaration : Declaration
{
    LinkageAttribute linkage;

    Type returnType;
    Argument[] arguments;
    bool varargs;

    void setReturnType(Type t, Flag!"ref_" ref_ = No.ref_)
    {
    }
}

class EnumDeclaration : Declaration
{
    Type type;

    EnumMember[] members;
}

class EnumMember : Declaration
{
    Expression value;
}

class StructDeclaration : Declaration
{
    LinkageAttribute linkage;

    // FIXME Need to distinguish between no list and length 0 list
    TemplateArgumentDeclaration[] templateArguments;

    // TODO should this be field declaration?
    void addField(VariableDeclaration v)
    {
        // TODO
    }

    // TODO make sure that Declaration is appropriate here.
    void addClassLevelDeclaration(Declaration d)
    {
        // TODO
    }

    void addDeclaration(Declaration d)
    {
        // TODO
        // Needs to determine whether d is a class level or instance level decl
    }
}

class SpecializedStructDeclaration : Declaration
{
    TemplateArgument[] templateArguments;
}

class AliasThisDeclaration : Declaration
{
    Declaration target;
}

class TemplateArgumentDeclaration : Declaration
{
}

class TemplateTypeArgumentDeclaration : TemplateArgumentDeclaration
{
    Type defaultType;
}

class TemplateValueArgumentDeclaration : TemplateArgumentDeclaration
{
    Type type;
    Expression defaultValue;
}

class MethodDeclaration : FunctionDeclaration
{
    Flag!"const_" const_;
    Flag!"virtual_" virtual_;
}

class InterfaceDeclaration : Declaration
{
    LinkageAttribute linkage;
    InterfaceDeclaration bases;

    // FIXME Need to distinguish between no list and length 0 list
    TemplateArgumentDeclaration[] templateArguments;

    void addBaseType(Type b)
    {
        // TODO
    }

    void addDeclaration(Declaration d)
    {
        // TODO
        // Needs to determine whether d is a class level or instance level decl
    }
}

class UnionDeclaration : Declaration
{
    LinkageAttribute linkage;

    // FIXME Need to distinguish between no list and length 0 list
    TemplateArgumentDeclaration[] templateArguments;

    void addDeclaration(Declaration d)
    {
        // TODO
        // Needs to determine whether d is a class level or instance level decl
    }
}

class AliasTypeDeclaration : Declaration
{
    LinkageAttribute linkage;
    Type type;
}

// An specific value of a template argument
class TemplateArgument
{
}

class TemplateTypeArgument : TemplateArgument
{
    this(Type)
    {
        // TODO
    }
}

class TemplateExpressionArgument : TemplateArgument
{
    this(Expression)
    {
        // TODO
    }
}

class Expression
{
}

class IntegerLiteralExpression : Expression
{
    this(long)
    {
        // TODO
    }
}

class BoolLiteralExpression : Expression
{
    this(bool)
    {
        // TODO
    }
}

class CastExpression : Expression
{
    Type type;
    Expression argument;
}

class PointerType : Type
{
    Type targetType;

    this(Type t)
    {
        targetType = t;
    }
}

class FunctionType : Type
{
    Type returnType;

    bool varargs;
    Type[] arguments;
}

// FIXME combine with argument declaration
class ArgumentType : Type
{
    Type type;
    Flag!"ref_" ref_;
}

class ArrayType : Type
{
    Type elementType;
    Expression length;
}

// A type that we have been instructed to replace with a specific name
class ReplacedType : Type
{
    IdentifierOrTemplateChain fullyQualifiedName;
}

// Used in the body of a template to refer to a type that is a parameter of the
// template.  Paul thinks.  Maybe...
class TemplateArgumentType : Type
{
    string name;
}
