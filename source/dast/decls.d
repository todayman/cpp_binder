/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2015-2016 Paul O'Neil <redballoon36@gmail.com>
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

import std.algorithm : filter, map, splitter;
import std.array : array;
import std.conv : to;
import std.stdio;
import std.typecons : Flag, No, Nullable;

static import std.d.ast;
import std.d.lexer;

static import dlang_decls;
import dast.common;
import dast.type;
import dast.expr;

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
        decl.parentModule = this;
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
            foreach (nsDepth, ns; namespace_chain)
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
                    next_namespace.name = new std.d.ast.IdentifierChain();
                    next_namespace.name.identifiers = namespace_chain[0 .. nsDepth+1].map!(tokenFromString).array;

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
            std.d.ast.Declaration concrete = decl.buildConcreteDecl();
            result.declarations ~= [concrete];
        }

        foreach (const Namespace ns; namespaces.byValue())
        {
            result.declarations ~= [ns.buildConcreteDecl()];
        }
        return result;
    }
}

public class Declaration
{
    // FIXME the fact that this is different than parent is a hack
    Module parentModule;
    private Declaration parent;
    // Do all declarations have visibility?
    Visibility visibility;

    string name;

    abstract pure std.d.ast.Declaration buildConcreteDecl() const;

    bool isNested() const pure
    {
        // Modules are not declarations, so
        // if we have parent, then we are nested
        return parent !is null;
    }

    private void addLinkage(std.d.ast.Declaration result, const(LinkageAttribute) linkage) const pure
    {
        // TODO should we always have a linkage?
        // TODO should check the scenarios where we cannot have linkage, e.g. methods?
        if (linkage && !isNested())
        {
            auto attr = linkage.buildConcreteAttribute();
            result.attributes ~= [attr];
        }
    }

    private void addVisibility(std.d.ast.Declaration result) const pure
    {
        auto attr = new std.d.ast.Attribute();

        final switch (visibility)
        {
            case Visibility.Public:
                attr.attribute = Token(tok!"public", "", 0, 0, 0);
                break;
            case Visibility.Private:
                attr.attribute = Token(tok!"private", "", 0, 0, 0);
                break;
            case Visibility.Protected:
                attr.attribute = Token(tok!"protected", "", 0, 0, 0);
                break;
            case Visibility.Export:
                attr.attribute = Token(tok!"export", "", 0, 0, 0);
                break;
            case Visibility.Package:
                attr.attribute = Token(tok!"package", "", 0, 0, 0);
                break;
        }
        result.attributes ~= [attr];
    }

    // FIXME doesn't work for symbols inside a namespace
    const(Token)[] qualifiedPath() const pure
    {
        if (parent is null)
        {
            if (parentModule !is null)
            {
                return parentModule.moduleName.identifiers ~ [tokenFromString(name)];
            }
            else
            {
                // TODO this means I am in the global namespace There should
                // probably be a prepended dot on the rendered name.
                return [tokenFromString(name)];
            }
        }
        else
        {
            return parent.qualifiedPath() ~ [tokenFromString(name)];
        }
    }

    void setParent(Declaration p)
    in {
        assert(p !is this);
    }
    body {
        parent = p;
    }

    const(Declaration) getParent() inout
    {
        return parent;
    }

    abstract pure string typestring() const;
}

public class Namespace
{
    std.d.ast.IdentifierChain name;
    Declaration[] declarations;

    pure
    std.d.ast.Declaration buildConcreteDecl() const
    in {
        assert (name !is null);
    }
    body {
        auto result = new std.d.ast.Declaration();
        // FIXME convert to linkage attribute
        auto linkAttr = new std.d.ast.Attribute();
        linkAttr.linkageAttribute = new std.d.ast.LinkageAttribute();
        linkAttr.linkageAttribute.identifier = tokenFromString("C");
        linkAttr.linkageAttribute.hasPlusPlus = true;
        linkAttr.linkageAttribute.identifierChain = new std.d.ast.IdentifierChain();
        linkAttr.linkageAttribute.identifierChain.identifiers = name.identifiers.dup;
        result.attributes ~= [linkAttr];

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
        auto result = new std.d.ast.Declaration();
        auto varDecl = new std.d.ast.VariableDeclaration();
        result.variableDeclaration = varDecl;

        varDecl.type = type.buildConcreteType();

        auto declarator = new std.d.ast.Declarator();
        declarator.name = tokenFromString(name);
        varDecl.declarators = [declarator];

        addLinkage(result, linkage);

        if (extern_)
        {
            auto sc = new std.d.ast.StorageClass();
            sc.token = Token(tok!"extern", "", 0, 0, 0);
            varDecl.storageClasses ~= [sc];
        }

        if (static_)
        {
            auto sc = new std.d.ast.StorageClass();
            sc.token = Token(tok!"static", "", 0, 0, 0);
            varDecl.storageClasses ~= [sc];
        }

        addVisibility(result);

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
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
        result.linkageAttribute.identifier = tokenFromString("C");

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
        auto result = new std.d.ast.Attribute();
        result.linkageAttribute = new std.d.ast.LinkageAttribute();
        result.linkageAttribute.identifier = tokenFromString("C");
        result.linkageAttribute.hasPlusPlus = true;

        if (namespacePath.length > 0)
        {
            auto chain = new std.d.ast.IdentifierChain();
            chain.identifiers = namespacePath
                .map!(tokenFromString).array;

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
        // TODO handle ref
        auto result = new std.d.ast.Parameter();
        result.type = type.buildConcreteType();
        if (name.length > 0)
        {
            result.name = tokenFromString(name);
        }

        return result;
    }
}

class FunctionDeclaration : Declaration
{
    LinkageAttribute linkage;

    Type returnType;
    Argument[] arguments;
    bool varargs;
    // TODO do I need static? or do those come through as functions?

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
        funcDecl.name = tokenFromString(name);
        funcDecl.parameters = new std.d.ast.Parameters();
        // TODO deal with varargs

        foreach (const Argument arg; arguments)
        {
            funcDecl.parameters.parameters ~= [arg.buildConcreteArgument()];
        }

        addLinkage(result, linkage);

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class EnumDeclaration : Declaration
{
    Type type;

    EnumMember[] members;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();
        auto enumDecl = new std.d.ast.EnumDeclaration();
        result.enumDeclaration = enumDecl;

        enumDecl.name = tokenFromString(name);
        enumDecl.type = type.buildConcreteType();
        enumDecl.enumBody = new std.d.ast.EnumBody();
        enumDecl.enumBody.enumMembers = members.map!(m => m.buildEnumMember()).array;

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
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

    pure
    std.d.ast.EnumMember buildEnumMember() const
    {
        auto result = new std.d.ast.EnumMember();
        result.name = tokenFromString(name);

        if (value !is null)
        {
            result.assignExpression = value.buildConcreteExpression();
        }

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

// Needs this name for eponymous template trick to work,
// but I'd really like a different, more explanatory name
mixin template buildConcreteType()
{
    pure
    std.d.ast.Type buildConcreteType() const
    {
        auto result = new std.d.ast.Type();
        result.type2 = new std.d.ast.Type2();
        result.type2.symbol = new std.d.ast.Symbol();
        result.type2.symbol.dot = false; // TODO maybe it shouldn't always be?
        result.type2.symbol.identifierOrTemplateChain = new std.d.ast.IdentifierOrTemplateChain();
        result.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances
            = map!(dlang_decls.makeInstance)(qualifiedPath).array;
        return result;
    }
}

struct TemplateArgumentList
{
    Nullable!(TemplateArgumentDeclaration[]) args;
    alias args this;

    this(TemplateArgumentDeclaration[] a)
    {
        args = a;
    }

    pure
    std.d.ast.TemplateParameters buildConcreteList() const
    {
        if (!args.isNull)
        {
            auto templateParameters = new std.d.ast.TemplateParameters();
            templateParameters.templateParameterList = new std.d.ast.TemplateParameterList();
            auto items = args.get().map!(param => param.buildTemplateParameter()).array;
            templateParameters.templateParameterList.items = items;
            return templateParameters;
        }
        else
        {
            return null;
        }
    }
}

// If there is a template<typename T>, this struct represents <int>
struct TemplateArgumentInstanceList
{
    Nullable!(TemplateArgumentInstance[]) arguments;
    alias arguments this;

    this(TemplateArgumentInstance[] a)
    {
        arguments = a;
    }

    pure std.d.ast.TemplateArguments buildConcreteList() const
    in {
        assert(!arguments.isNull());
    }
    body {
        // FIXME use the template single argument syntax?
        auto argList = new std.d.ast.TemplateArgumentList();
        argList.items = arguments.get().map!(a => a.buildConcreteArgument()).array;
        auto args = new std.d.ast.TemplateArguments();
        args.templateArgumentList = argList;
        return args;
    }
}

// A specific value of a template argument
interface TemplateArgumentInstance
{
    pure std.d.ast.TemplateArgument buildConcreteArgument() const;
}

class TemplateTypeArgumentInstance : TemplateArgumentInstance
{
    private Type type;

    this(Type t)
    {
        type = t;
    }

    override pure
    std.d.ast.TemplateArgument buildConcreteArgument() const
    {
        auto result = new std.d.ast.TemplateArgument();
        result.type = type.buildConcreteType();
        return result;
    }
}

class TemplateValueArgumentInstance : TemplateArgumentInstance
{
    private Expression exp;

    this(Expression e)
    in {
        assert (e !is null);
    }
    body {
        exp = e;
    }

    override pure
    std.d.ast.TemplateArgument buildConcreteArgument() const
    {
        auto result = new std.d.ast.TemplateArgument();
        result.assignExpression = exp.buildConcreteExpression();
        return result;
    }
}

class StructDeclaration : Declaration, Type
{
    LinkageAttribute linkage;

    TemplateArgumentList templateArguments;

    VariableDeclaration[] fields;
    MethodDeclaration[] methods;

    Declaration[] classDeclarations;

    // TODO should this be field declaration?
    void addField(VariableDeclaration v)
    {
        // TODO
        v.setParent(this);
        fields ~= [v];
    }

    void addMethod(MethodDeclaration f)
    {
        f.setParent(this);
        methods ~= [f];
    }

    // TODO make sure that Declaration is appropriate here.
    void addClassLevelDeclaration(Declaration d)
    {
        d.setParent(this);
        classDeclarations ~= [d];
    }

    void addClassLevelVariable(VariableDeclaration d)
    {
        d.setParent(this);
        classDeclarations ~= [d];
        d.static_ = true;
    }

    void addDeclaration(Declaration d)
    {
        // TODO
        // Needs to determine whether d is a class level or instance level decl
        auto varDecl = cast(VariableDeclaration)d;
        if (varDecl !is null)
        {
            if (varDecl.static_)
            {
                addClassLevelVariable(varDecl);
            }
            else
            {
                addField(varDecl);
            }
        }
        else
        {
            auto methodDecl = cast(MethodDeclaration)d;
            if (methodDecl !is null)
            {
                addMethod(methodDecl);
            }
            else
            {
                addClassLevelDeclaration(d);
            }
        }
    }

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();
        auto structDecl = new std.d.ast.StructDeclaration();
        result.structDeclaration = structDecl;

        structDecl.name = tokenFromString(name);
        structDecl.templateParameters = templateArguments.buildConcreteList();

        structDecl.structBody = new std.d.ast.StructBody();

        foreach (field; fields)
        {
            structDecl.structBody.declarations ~= [field.buildConcreteDecl()];
        }
        foreach (method; methods)
        {
            structDecl.structBody.declarations ~= [method.buildConcreteDecl()];
        }
        foreach (decl; classDeclarations)
        {
            structDecl.structBody.declarations ~= [decl.buildConcreteDecl()];
        }
        // TODO

        addLinkage(result, linkage);

        return result;
    }

    // FIXME leaves off the template arguments.
    // Right now, that's what I want, but probably not what would be expected
    mixin .buildConcreteType!();

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

// Types of specialized templates are separate from the declarations since they
// may not actually be declared.
class SpecializedStructDeclaration : StructDeclaration
{
    TemplateArgumentInstanceList templateArguments;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

// TODO dedup with SpecializedStructDeclaration
class SpecializedInterfaceDeclaration : InterfaceDeclaration
{
    TemplateArgumentInstanceList templateArguments;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
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

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

// Maybe these shouldn't be declarations?  We need the "declaration" to be a
// std.d.ast.TemplateParameter, so I've added a method here.  But now the
// Declaration part of this type isn't used anymore.
class TemplateArgumentDeclaration : Declaration
{
    pure abstract
    std.d.ast.TemplateParameter buildTemplateParameter() const;

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class TemplateTypeArgumentDeclaration : TemplateArgumentDeclaration, Type
{
    Type defaultType;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    mixin .buildConcreteType!();

    override pure
    std.d.ast.TemplateParameter buildTemplateParameter() const
    {
        auto result = new std.d.ast.TemplateParameter();
        result.templateTypeParameter = new std.d.ast.TemplateTypeParameter();
        // TODO deal with default types, specific specializations, etc.
        result.templateTypeParameter.identifier = tokenFromString(name);

        if (defaultType !is null)
        {
            result.templateTypeParameter.assignType = defaultType.buildConcreteType();
        }

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class TemplateValueArgumentDeclaration : TemplateArgumentDeclaration, Expression
{
    Type type;
    Expression defaultValue;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    override pure
    std.d.ast.TemplateParameter buildTemplateParameter() const
    {
        auto result = new std.d.ast.TemplateParameter();
        result.templateValueParameter = new std.d.ast.TemplateValueParameter();
        result.templateValueParameter.type = type.buildConcreteType();
        result.templateValueParameter.identifier = tokenFromString(name);
        // TODO deal with defaultValue

        if (defaultValue !is null)
        {
            auto default_ = new std.d.ast.TemplateValueParameterDefault();
            default_.assignExpression = defaultValue.buildConcreteExpression();
            result.templateValueParameter.templateValueParameterDefault = default_;
        }

        return result;
    }

    override pure
    std.d.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new std.d.ast.PrimaryExpression();
        result.primary = tokenFromString(name);
        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class MethodDeclaration : FunctionDeclaration
{
    Flag!"const_" const_;
    Flag!"virtual_" virtual_;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = FunctionDeclaration.buildConcreteDecl();
        auto methodDecl = result.functionDeclaration;
        assert(methodDecl !is null);
        if (const_)
        {
            auto attr = new std.d.ast.MemberFunctionAttribute();
            attr.tokenType = tok!"const";
            methodDecl.memberFunctionAttributes ~= [attr];
        }

        addVisibility(result);

        if (!virtual_)
        {
            auto attr = new std.d.ast.Attribute();
            attr.attribute = Token(tok!"final", "", 0, 0, 0);
            result.attributes ~= [attr];
        }

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class InterfaceDeclaration : Declaration, Type
{
    // FIXME dedup this class with StructDeclaration

    LinkageAttribute linkage;
    InterfaceDeclaration bases;

    TemplateArgumentList templateArguments;

    MethodDeclaration[] methods;

    Declaration[] classDeclarations;

    void addMethod(MethodDeclaration f)
    {
        f.setParent(this);
        methods ~= [f];
    }

    // TODO make sure that Declaration is appropriate here.
    void addClassLevelDeclaration(Declaration d)
    {
        d.setParent(this);
        classDeclarations ~= [d];
    }

    void addClassLevelVariable(VariableDeclaration d)
    {
        d.setParent(this);
        classDeclarations ~= [d];
        d.static_ = true;
    }

    void addDeclaration(Declaration d)
    {
        // TODO
        // Needs to determine whether d is a class level or instance level decl
        auto varDecl = cast(VariableDeclaration)d;
        if (varDecl !is null)
        {
            if (varDecl.static_)
            {
                addClassLevelVariable(varDecl);
            }
            else
            {
                throw new Exception("Cannot add instance level variables to an interface");
            }
        }
        else
        {
            auto methodDecl = cast(MethodDeclaration)d;
            if (methodDecl !is null)
            {
                addMethod(methodDecl);
            }
            else
            {
                addClassLevelDeclaration(d);
            }
        }
    }

    void addBaseType(Type b)
    {
        // TODO
        assert(0);
    }


    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();
        auto interfaceDecl = new std.d.ast.InterfaceDeclaration();
        result.interfaceDeclaration = interfaceDecl;

        interfaceDecl.name = tokenFromString(name);
        interfaceDecl.templateParameters = templateArguments.buildConcreteList();

        auto body_ = new std.d.ast.StructBody();

        foreach (method; methods)
        {
            body_.declarations ~= [method.buildConcreteDecl()];
        }
        foreach (decl; classDeclarations)
        {
            body_.declarations ~= [decl.buildConcreteDecl()];
        }
        interfaceDecl.structBody = body_;
        // TODO

        addLinkage(result, linkage);

        return result;
    }

    mixin .buildConcreteType!();

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class UnionDeclaration : Declaration, Type
{
    LinkageAttribute linkage;

    // FIXME Need to distinguish between no list and length 0 list
    TemplateArgumentList templateArguments;

    VariableDeclaration[] fields;
    MethodDeclaration[] methods;

    // TODO should this be field declaration?
    void addField(VariableDeclaration v)
    {
        // TODO
        v.setParent(this);
        fields ~= [v];
    }

    // TODO should this be method declaration?
    void addMethod(MethodDeclaration f)
    {
        f.setParent(this);
        methods ~= [f];
    }

    // TODO make sure that Declaration is appropriate here.
    void addClassLevelDeclaration(Declaration d)
    {
        // TODO
        assert(0);
    }

    void addDeclaration(Declaration d)
    {
        // TODO
        // Needs to determine whether d is a class level or instance level decl
        auto varDecl = cast(VariableDeclaration)d;
        if (varDecl !is null)
        {
            if (varDecl.static_)
            {
                addClassLevelDeclaration(varDecl);
            }
            else
            {
                addField(varDecl);
            }
        }
        else
        {
            auto methodDecl = cast(MethodDeclaration)d;
            if (methodDecl !is null)
            {
                addMethod(methodDecl);
            }
            else
            {
                addClassLevelDeclaration(d);
            }
        }
    }

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();
        auto unionDecl = new std.d.ast.UnionDeclaration();
        result.unionDeclaration = unionDecl;

        if (name.length)
        {
            unionDecl.name = tokenFromString(name);
        }

        unionDecl.templateParameters = templateArguments.buildConcreteList();

        unionDecl.structBody = new std.d.ast.StructBody();

        foreach (field; fields)
        {
            unionDecl.structBody.declarations ~= [field.buildConcreteDecl()];
        }
        foreach (method; methods)
        {
            unionDecl.structBody.declarations ~= [method.buildConcreteDecl()];
        }
        // TODO

        addLinkage(result, linkage);
        addVisibility(result);

        return result;
    }

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class AliasTypeDeclaration : Declaration, Type
{
    LinkageAttribute linkage;
    Type type;

    override pure
    std.d.ast.Declaration buildConcreteDecl() const
    {
        auto result = new std.d.ast.Declaration();
        auto aliasDecl = new std.d.ast.AliasDeclaration();
        result.aliasDeclaration = aliasDecl;

        auto initializer = new std.d.ast.AliasInitializer();
        initializer.name = tokenFromString(name);
        initializer.type = type.buildConcreteType();
        aliasDecl.initializers = [initializer];

        addLinkage(result, linkage);
        addVisibility(result);

        return result;
    }

    mixin .buildConcreteType!();

    override pure string typestring() const
    {
        return typeof(this).stringof;
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
