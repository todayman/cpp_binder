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
import std.typecons : Flag, No;

static import std.d.ast;
import std.d.lexer;

static import dlang_decls;

Token tokenFromString(string name) pure nothrow @nogc @safe
{
    return Token(tok!"identifier", name, 0, 0, 0);
}

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
    Declaration parent;
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
}

class StructDeclaration : Declaration, Type
{
    LinkageAttribute linkage;

    // FIXME Need to distinguish between no list and length 0 list
    TemplateArgumentDeclaration[] templateArguments;

    VariableDeclaration[] fields;
    MethodDeclaration[] methods;

    Declaration[] classDeclarations;

    // TODO should this be field declaration?
    void addField(VariableDeclaration v)
    {
        // TODO
        v.parent = this;
        fields ~= [v];
    }

    void addMethod(MethodDeclaration f)
    {
        f.parent = this;
        methods ~= [f];
    }

    // TODO make sure that Declaration is appropriate here.
    void addClassLevelDeclaration(Declaration d)
    {
        d.parent = this;
        classDeclarations ~= [d];
    }

    void addClassLevelVariable(VariableDeclaration d)
    {
        d.parent = this;
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

    override pure
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
}

class InterfaceDeclaration : Declaration, Type
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

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}

class UnionDeclaration : Declaration, Type
{
    LinkageAttribute linkage;

    // FIXME Need to distinguish between no list and length 0 list
    TemplateArgumentDeclaration[] templateArguments;

    VariableDeclaration[] fields;
    MethodDeclaration[] methods;

    // TODO should this be field declaration?
    void addField(VariableDeclaration v)
    {
        // TODO
        v.parent = this;
        fields ~= [v];
    }

    // TODO should this be method declaration?
    void addMethod(MethodDeclaration f)
    {
        f.parent = this;
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

        return result;
    }

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        // FIXME copy pasted from StructDeclaration
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

class ConstType : Type
{
    Type target;

    this(Type t)
    {
        target = t;
    }

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        auto result = new std.d.ast.Type();
        result.type2 = new std.d.ast.Type2();
        result.type2.typeConstructor = tok!"const";
        result.type2.type = target.buildConcreteType().deepDup();

        return result;
    }
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

// TODO move this to dast.expr.d
class Expression
{
    abstract pure std.d.ast.ExpressionNode buildConcreteExpression() const;
}

class IntegerLiteralExpression : Expression
{
    long value;
    this(long v)
    {
        value = v;
    }

    override pure
    std.d.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new std.d.ast.PrimaryExpression();
        result.primary = tokenFromString(to!string(value));
        return result;
    }
}

class BoolLiteralExpression : Expression
{
    bool value;

    this(bool v)
    {
        value = v;
    }

    override pure
    std.d.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new std.d.ast.PrimaryExpression();
        result.primary = Token((value ? tok!"true" : tok!"false"), "", 0, 0, 0);
        return result;
    }
}

class CastExpression : Expression
{
    Type type;
    Expression argument;

    override pure
    std.d.ast.ExpressionNode buildConcreteExpression() const
    {
        assert(0);
    }
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
        auto result = targetType.buildConcreteType().deepDup();

        auto starSuffix = new std.d.ast.TypeSuffix();
        starSuffix.star = Token(tok!"*", "", 0, 0, 0);
        result.typeSuffixes ~= [starSuffix];

        return result;
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

std.d.ast.Type deepDup(const(std.d.ast.Type) src) pure
{
    if (src is null)
    {
        return null;
    }

    auto result = new std.d.ast.Type();
    result.typeConstructors = src.typeConstructors.dup;
    result.typeSuffixes = src.typeSuffixes.map!(deepDup).array;
    result.type2 = deepDup(src.type2);
    return result;
}

std.d.ast.TypeSuffix deepDup(const(std.d.ast.TypeSuffix) src) pure
{
    auto result = new std.d.ast.TypeSuffix();
    result.delegateOrFunction = src.delegateOrFunction;
    result.star = src.star;
    result.array = src.array;
    if (src.type) result.type = deepDup(src.type);
    assert(src.low is null); // TODO
    assert(src.high is null); // TODO
    assert(src.parameters is null); // TODO
    assert(src.memberFunctionAttributes.length == 0); // TODO

    return result;
}

std.d.ast.Type2 deepDup(const(std.d.ast.Type2) src) pure
{
    auto result = new std.d.ast.Type2();
    result.builtinType = src.builtinType;
    result.symbol = deepDup(src.symbol);
    assert(src.typeofExpression is null);
    result.identifierOrTemplateChain = deepDup(src.identifierOrTemplateChain);
    result.typeConstructor = src.typeConstructor;
    result.type = deepDup(src.type);
    assert(src.vector is null);

    return result;
}

std.d.ast.Symbol deepDup(const(std.d.ast.Symbol) src) pure
{
    auto result = new std.d.ast.Symbol();
    result.identifierOrTemplateChain = deepDup(src.identifierOrTemplateChain);
    result.dot = src.dot;
    return result;
}

std.d.ast.IdentifierOrTemplateChain deepDup(const(std.d.ast.IdentifierOrTemplateChain) src) pure
{
    if (src is null)
    {
        return null;
    }

    auto result = new std.d.ast.IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances = deepDup(src.identifiersOrTemplateInstances);
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
