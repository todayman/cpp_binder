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

module dast.decls;

import std.algorithm : filter, splitter;
import std.array : array;
import std.stdio;
import std.typecons : Flag, No;

static import std.d.ast;
import std.d.lexer;

static import dlang_decls;

class Module
{
    protected:
    immutable std.d.ast.IdentifierChain moduleName;
    Namespace[string] namespaces;
    Declaration[] declarations;

    public:
    this(string path)
    {
        moduleName = dlang_decls.makeIdentifierChain(path);
    }

    void addDeclaration(Declaration decl, string namespace)
    {
        if (namespace == "")
        {
            declarations ~= [decl];
            return;
        }

        if (auto dest = namespace in namespaces)
        {
            dest.declarations ~= [decl];
        }
        else {
            import std.array : appender;
            import std.exception : assumeUnique;

            immutable(string[]) namespace_chain =
                namespace.splitter("::").filter!(a => a.length != 0).array.assumeUnique;
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
                    /+if (parent_namespace is null)
                    {
                        declarations ~= [next_namespace];
                    }
                    else
                    {
                        parent_namespace.declarations ~= [next_namespace];
                    }+/
                    parent_namespace = next_namespace;
                }
            }

            parent_namespace.declarations ~= [decl];
        }
    }

    bool empty() const
    {
        // TODO check that namespaces are only created when something is put
        // into them.
        return namespaces.length == 0 && declarations.length == 0;
    }

    immutable(std.d.ast.IdentifierChain) name() const
    {
        return moduleName;
    }

    std.d.ast.Module buildConcreteTree() const
    {
        auto result = new std.d.ast.Module();
        result.moduleDeclaration = new std.d.ast.ModuleDeclaration();
        result.moduleDeclaration.moduleName = new std.d.ast.IdentifierChain();
        result.moduleDeclaration.moduleName.identifiers = name.identifiers.dup;

        foreach (const Declaration decl; declarations)
        {
            import std.d.formatter : format;
            std.d.ast.Declaration concrete = decl.buildConcreteDecl();
            result.declarations ~= [concrete];
        }
        return result;
    }
}

public class Declaration
{
    Declaration parent;
    // Do all declarations have visibility?
    Visibility visibility;

    string name;

    abstract pure std.d.ast.Declaration buildConcreteDecl() const;

    bool insideNamespace() const pure @nogc nothrow
    {
        const(Declaration) cur = parent;
        while (cur !is null)
        {
            if (cast(const(Namespace))cur !is null)
            {
                return true;
            }
        }

        return false;
    }
}

public class Namespace
{
    std.d.ast.IdentifierChain name;
    Declaration[] declarations;

    pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();
        auto linkAttr = new std.d.ast.Attribute();
        linkAttr.linkageAttribute = new std.d.ast.LinkageAttribute();
        linkAttr.linkageAttribute.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        linkAttr.linkageAttribute.hasPlusPlus = true;
        linkAttr.linkageAttribute.identifierChain = new std.d.ast.IdentifierChain();
        linkAttr.linkageAttribute.identifierChain.identifiers = name.identifiers.dup;

        foreach (const Declaration subdecl; declarations)
        {
            result.declarations ~= [subdecl.buildConcreteDecl()];
        }

        return result;
    }
}

public class VariableDeclaration : Declaration
{
    Type type;
    // modifiers
    bool extern_;
    bool static_;
    LinkageAttribute linkage; // language linkage

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

public class FieldDeclaration : Declaration
{
    Type type;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

class LinkageAttribute
{
    public abstract pure std.d.ast.Attribute buildConcreteAttribute() const;
}

class CLinkageAttribute : LinkageAttribute
{
    override pure
    public std.d.ast.Attribute buildConcreteAttribute() const
    {
        auto result = new std.d.ast.Attribute();
        result.linkageAttribute = new std.d.ast.LinkageAttribute();
        result.linkageAttribute.identifier = Token(tok!"identifier", "C", 0, 0, 0);

        return result;
    }
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

    override pure
    public std.d.ast.Attribute buildConcreteAttribute() const
    {
        import std.algorithm : map;

        auto result = new std.d.ast.Attribute();
        result.linkageAttribute = new std.d.ast.LinkageAttribute();
        result.linkageAttribute.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        result.linkageAttribute.hasPlusPlus = true;

        if (namespacePath.length > 0)
        {
            auto chain = new std.d.ast.IdentifierChain();
            chain.identifiers = namespacePath
                .map!(str => Token(tok!"identifier", str, 0, 0, 0)).array;

            result.linkageAttribute.identifierChain = chain;
        }

        return result;
    }
}

class Argument
{
    string name;
    Type type;
    Flag!"ref_" ref_;

    pure std.d.ast.Parameter buildConcreteArgument() const
    {
        assert(0);
    }
}

class FunctionDeclaration : Declaration
{
    LinkageAttribute linkage;

    Type returnType;
    Argument[] arguments;
    bool varargs;

    void setReturnType(Type t, Flag!"ref_" ref_ = No.ref_)
    {
        returnType = t;
        // TODO deal with ref
    }

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();

        auto funcDecl = new std.d.ast.FunctionDeclaration();
        result.functionDeclaration = funcDecl;
        // TODO deal with ref return type
        funcDecl.returnType = returnType.buildConcreteType();
        funcDecl.name = Token(tok!"identifier", name, 0, 0, 0);
        funcDecl.parameters = new std.d.ast.Parameters();
        // TODO deal with varargs

        foreach (const Argument arg; arguments)
        {
            funcDecl.parameters.parameters ~= [arg.buildConcreteArgument()];
        }

        if (!insideNamespace()) // Are there other places too?
        {
            auto attr = linkage.buildConcreteAttribute();
            result.attributes ~= [attr];
        }

        return result;
    }
}

class EnumDeclaration : Declaration
{
    Type type;

    EnumMember[] members;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

class EnumMember : Declaration
{
    Expression value;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
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

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();

        // TODO

        return result;
    }
}

class SpecializedStructDeclaration : Declaration
{
    TemplateArgument[] templateArguments;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

class AliasThisDeclaration : Declaration
{
    Declaration target;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

class TemplateArgumentDeclaration : Declaration
{
}

class TemplateTypeArgumentDeclaration : TemplateArgumentDeclaration
{
    Type defaultType;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

class TemplateValueArgumentDeclaration : TemplateArgumentDeclaration
{
    Type type;
    Expression defaultValue;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
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

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
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

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

class AliasTypeDeclaration : Declaration
{
    LinkageAttribute linkage;
    Type type;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
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
    abstract pure std.d.ast.Type buildConcreteType() const;
}

class ReturnType
{
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

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}

class FunctionType : Type
{
    Type returnType;

    bool varargs;
    Type[] arguments;

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}

// FIXME combine with argument declaration
class ArgumentType : Type
{
    Type type;
    Flag!"ref_" ref_;

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}

class ArrayType : Type
{
    Type elementType;
    Expression length;

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}

std.d.ast.IdentifierOrTemplateInstance[] deepDup(const(std.d.ast.IdentifierOrTemplateInstance)[] arr) pure
{
    auto result = new std.d.ast.IdentifierOrTemplateInstance[arr.length];
    foreach (index, const a; arr)
    {
        result[index] = new std.d.ast.IdentifierOrTemplateInstance();
        result[index].identifier = a.identifier;
        if (a.templateInstance)
        {
            result[index].templateInstance = deepDup(a.templateInstance);
        }
    }

    return result;
}

std.d.ast.TemplateInstance deepDup(const(std.d.ast.TemplateInstance) src) pure
{
    auto result = new std.d.ast.TemplateInstance();
    result.identifier = src.identifier;
    result.templateArguments = deepDup(src.templateArguments);
    return result;
}

std.d.ast.TemplateArguments deepDup(const(std.d.ast.TemplateArguments) src) pure
{
    auto result = new std.d.ast.TemplateArguments();
    result.templateArgumentList = deepDup(src.templateArgumentList);
    result.templateSingleArgument = deepDup(src.templateSingleArgument);
    return result;
}

std.d.ast.TemplateArgumentList deepDup(const(std.d.ast.TemplateArgumentList) src) pure
{
    auto result = new std.d.ast.TemplateArgumentList();
    result.items = new std.d.ast.TemplateArgument[src.items.length];
    foreach (index, const item; src.items)
    {
        result.items[index] = deepDup(item);
    }
    return result;
}

std.d.ast.TemplateArgument deepDup(const(std.d.ast.TemplateArgument) src) pure
{
    auto result = new std.d.ast.TemplateArgument();
    result.type = null; // TODO fill in
    result.assignExpression = null; // TODO fill in
    return result;
}

std.d.ast.TemplateSingleArgument deepDup(const(std.d.ast.TemplateSingleArgument) src) pure
{
    auto result = new std.d.ast.TemplateSingleArgument();
    result.token = src.token;
    return result;
}

// A type that we have been instructed to replace with a specific name
class ReplacedType : Type
{
    // TODO do I really want to be using this type?
    std.d.ast.IdentifierOrTemplateChain fullyQualifiedName;

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        auto result = new std.d.ast.Type();
        result.type2 = new std.d.ast.Type2();
        result.type2.symbol = new std.d.ast.Symbol();
        result.type2.symbol.dot = false; // TODO maybe it shouldn't always be?
        result.type2.symbol.identifierOrTemplateChain = new std.d.ast.IdentifierOrTemplateChain();
        // FIXME why do I need the template argument on dup?
        result.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances
            = fullyQualifiedName.identifiersOrTemplateInstances.deepDup;
        return result;
    }
}

// Used in the body of a template to refer to a type that is a parameter of the
// template.  Paul thinks.  Maybe...
class TemplateArgumentType : Type
{
    string name;

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}
