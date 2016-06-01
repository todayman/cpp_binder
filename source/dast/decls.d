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

static import dparse.ast;
import dparse.lexer;

static import dlang_decls;
import dast.common;
import dast.type;
import dast.expr;

class Module
{
    protected:
    immutable dparse.ast.IdentifierChain moduleName;
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
                    next_namespace.name = new dparse.ast.IdentifierChain();
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

    immutable(dparse.ast.IdentifierChain) name() const
    {
        return moduleName;
    }

    dparse.ast.Module buildConcreteTree() const
    {
        auto result = new dparse.ast.Module();
        result.moduleDeclaration = new dparse.ast.ModuleDeclaration();
        result.moduleDeclaration.moduleName = new dparse.ast.IdentifierChain();
        result.moduleDeclaration.moduleName.identifiers = name.identifiers.dup;

        foreach (const Declaration decl; declarations)
        {
            if (!decl.shouldEmit) continue;
            dparse.ast.Declaration concrete = decl.buildConcreteDecl();
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

    // Should be pure, but dparse.ast.Declaration accessors / setters aren't
    // pure because methods on std.Variant aren't pure.
    abstract dparse.ast.Declaration buildConcreteDecl() const;

    bool isNested() const pure
    {
        // Modules are not declarations, so
        // if we have parent, then we are nested
        return parent !is null;
    }

    private void addLinkage(dparse.ast.Declaration result, const(LinkageAttribute) linkage) const pure
    {
        // TODO should we always have a linkage?
        // TODO should check the scenarios where we cannot have linkage, e.g. methods?
        if (linkage && !isNested())
        {
            auto attr = linkage.buildConcreteAttribute();
            result.attributes ~= [attr];
        }
    }

    private void addVisibility(dparse.ast.Declaration result) const pure
    {
        auto attr = new dparse.ast.Attribute();

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

    pure dparse.ast.IdentifierOrTemplateInstance unqualifiedName() const
    {
        auto inst = new dparse.ast.IdentifierOrTemplateInstance();
        inst.identifier = tokenFromString(name);
        return inst;
    }

    // FIXME doesn't work for symbols inside a namespace
    // Also doesn't work for templates
    dparse.ast.IdentifierOrTemplateInstance[] qualifiedPath() const pure
    {
        import dlang_decls : makeInstance;

        if (parent is null)
        {
            if (parentModule !is null)
            {
                return map!(makeInstance)(parentModule.moduleName.identifiers).array ~ [unqualifiedName()];
            }
            else
            {
                // TODO this means I am in the global namespace There should
                // probably be a prepended dot on the rendered name.
                return [unqualifiedName()];
            }
        }
        else
        {
            if (parent is this)
            {
                debug{stderr.writeln("name = ", name);}
                assert(0);
            }
            return parent.qualifiedPath() ~ [unqualifiedName()];
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

    // Things like specialized template declarations may not need to be emitted
    // if they are just instantiations of a template and not a distinct
    // specialization.  Default is to emit everything.
    pure bool shouldEmit() const
    {
        return true;
    }
}

public class Namespace
{
    dparse.ast.IdentifierChain name;
    Declaration[] declarations;

    dparse.ast.Declaration buildConcreteDecl() const
    in {
        assert (name !is null);
    }
    body {
        auto result = new dparse.ast.Declaration();
        // FIXME convert to linkage attribute
        auto linkAttr = new dparse.ast.Attribute();
        linkAttr.linkageAttribute = new dparse.ast.LinkageAttribute();
        linkAttr.linkageAttribute.identifier = tokenFromString("C");
        linkAttr.linkageAttribute.hasPlusPlus = true;
        linkAttr.linkageAttribute.identifierChain = new dparse.ast.IdentifierChain();
        linkAttr.linkageAttribute.identifierChain.identifiers = name.identifiers.dup;
        result.attributes ~= [linkAttr];

        foreach (const Declaration subdecl; declarations)
        {
            result.declarations ~= [subdecl.buildConcreteDecl()];
        }

        return result;
    }
}

public class VariableDeclaration : Declaration, Expression
{
    Type type;
    // modifiers
    bool extern_;
    bool static_;
    LinkageAttribute linkage; // language linkage

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        auto result = new dparse.ast.Declaration();
        auto varDecl = new dparse.ast.VariableDeclaration();
        result.variableDeclaration = varDecl;

        varDecl.type = type.buildConcreteType();

        auto declarator = new dparse.ast.Declarator();
        declarator.name = tokenFromString(name);
        varDecl.declarators = [declarator];

        addLinkage(result, linkage);

        if (extern_)
        {
            auto sc = new dparse.ast.StorageClass();
            sc.token = Token(tok!"extern", "", 0, 0, 0);
            varDecl.storageClasses ~= [sc];
        }

        if (static_)
        {
            auto sc = new dparse.ast.StorageClass();
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

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        assert(0);
    }
}

public class FieldDeclaration : Declaration
{
    Type type;

    override pure
    dparse.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
}

class LinkageAttribute
{
    public abstract pure dparse.ast.Attribute buildConcreteAttribute() const;
}

class CLinkageAttribute : LinkageAttribute
{
    override pure
    public dparse.ast.Attribute buildConcreteAttribute() const
    {
        auto result = new dparse.ast.Attribute();
        result.linkageAttribute = new dparse.ast.LinkageAttribute();
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
    public dparse.ast.Attribute buildConcreteAttribute() const
    {
        auto result = new dparse.ast.Attribute();
        result.linkageAttribute = new dparse.ast.LinkageAttribute();
        result.linkageAttribute.identifier = tokenFromString("C");
        result.linkageAttribute.hasPlusPlus = true;

        if (namespacePath.length > 0)
        {
            auto chain = new dparse.ast.IdentifierChain();
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

    pure dparse.ast.Parameter buildConcreteArgument() const
    {
        // TODO handle ref
        auto result = new dparse.ast.Parameter();
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

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        return buildConcreteDecl(null);
    }

    dparse.ast.Declaration buildConcreteDecl(dparse.ast.FunctionDeclaration* outParam) const
    {
        auto result = new dparse.ast.Declaration();

        auto funcDecl = new dparse.ast.FunctionDeclaration();
        result.functionDeclaration = funcDecl;
        // TODO deal with ref return type
        funcDecl.returnType = returnType.buildConcreteType();
        funcDecl.name = tokenFromString(name);
        funcDecl.parameters = new dparse.ast.Parameters();
        // TODO deal with varargs

        foreach (const Argument arg; arguments)
        {
            funcDecl.parameters.parameters ~= [arg.buildConcreteArgument()];
        }

        addLinkage(result, linkage);

        if (outParam !is null)
        {
            (*outParam) = funcDecl;
        }

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

// TODO Should this be a type? Need to check that the mangling is right
class EnumDeclaration : Declaration, Type
{
    Type type;

    EnumMember[] members;

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        auto result = new dparse.ast.Declaration();
        auto enumDecl = new dparse.ast.EnumDeclaration();
        result.enumDeclaration = enumDecl;

        enumDecl.name = tokenFromString(name);
        enumDecl.type = type.buildConcreteType();
        enumDecl.enumBody = new dparse.ast.EnumBody();
        enumDecl.enumBody.enumMembers = members.map!(m => m.buildEnumMember()).array;

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }

    override pure
    dparse.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}

class EnumMember : Declaration, Expression
{
    Expression value;

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    pure
    dparse.ast.EnumMember buildEnumMember() const
    {
        auto result = new dparse.ast.EnumMember();
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

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        assert(0);
    }
}

// Needs this name for eponymous template trick to work,
// but I'd really like a different, more explanatory name
mixin template buildConcreteType()
{
    pure
    dparse.ast.Type buildConcreteType() const
    {
        auto result = new dparse.ast.Type();
        result.type2 = new dparse.ast.Type2();
        result.type2.symbol = new dparse.ast.Symbol();
        result.type2.symbol.dot = false; // TODO maybe it shouldn't always be?
        result.type2.symbol.identifierOrTemplateChain = new dparse.ast.IdentifierOrTemplateChain();
        result.type2.symbol.identifierOrTemplateChain
            = dlang_decls.makeIdentifierOrTemplateChain(qualifiedPath());
        return result;
    }
}

struct TemplateArgumentList
{
    // FIXME Rename to be consistent with TemplateArgumentInstanceList
    Nullable!(TemplateArgumentDeclaration[]) args;
    alias args this;

    this(TemplateArgumentDeclaration[] a)
    {
        args = a;
    }

    pure
    dparse.ast.TemplateParameters buildConcreteList() const
    {
        if (!args.isNull)
        {
            auto templateParameters = new dparse.ast.TemplateParameters();
            templateParameters.templateParameterList = new dparse.ast.TemplateParameterList();
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
    // FIXME Rename to be consistent with TemplateArgumentList
    Nullable!(TemplateArgumentInstance[]) arguments;
    alias arguments this;

    this(TemplateArgumentInstance[] a)
    {
        arguments = a;
    }

    pure dparse.ast.TemplateArguments buildConcreteList() const
    in {
        assert(!arguments.isNull());
    }
    body {
        // FIXME use the template single argument syntax?
        auto argList = new dparse.ast.TemplateArgumentList();
        argList.items = arguments.get().map!(a => a.buildConcreteArgument()).array;
        auto args = new dparse.ast.TemplateArguments();
        args.templateArgumentList = argList;
        return args;
    }
}

// A specific value of a template argument
interface TemplateArgumentInstance
{
    pure dparse.ast.TemplateArgument buildConcreteArgument() const;
}

class TemplateTypeArgumentInstance : TemplateArgumentInstance
{
    private Type type;

    this(Type t)
    {
        type = t;
    }

    override pure
    dparse.ast.TemplateArgument buildConcreteArgument() const
    {
        auto result = new dparse.ast.TemplateArgument();
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
    dparse.ast.TemplateArgument buildConcreteArgument() const
    {
        auto result = new dparse.ast.TemplateArgument();
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

    void addDeclarations(Declaration[] ds)
    {
        foreach (d; ds)
        {
            addDeclaration(d);
        }
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

    pure dparse.ast.TemplateParameters buildTemplateList() const
    {
        return templateArguments.buildConcreteList();
    }

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        auto result = new dparse.ast.Declaration();
        auto structDecl = new dparse.ast.StructDeclaration();
        result.structDeclaration = structDecl;

        structDecl.name = tokenFromString(name);
        structDecl.templateParameters = buildTemplateList();

        structDecl.structBody = new dparse.ast.StructBody();

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
// We need these around so that we can reference declarations inside of them
// and use them in names and stuff, but they may not be emitted.
class SpecializedStructDeclaration : StructDeclaration
{
    TemplateArgumentInstanceList templateArgumentValues;

    bool shouldEmit_ = true;

    override pure
    bool shouldEmit() const
    {
        return shouldEmit_;
    }
    override pure
    dparse.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }
    protected override
    dparse.ast.TemplateParameters buildTemplateList() const
    {
        import std.range : zip;

        assert(!templateArguments.args.isNull);
        assert(!templateArgumentValues.arguments.isNull);

        auto result = new dparse.ast.TemplateParameters();
        result.templateParameterList = new dparse.ast.TemplateParameterList();
        foreach (pair; zip(templateArguments.args.get(), templateArgumentValues.arguments.get()))
        {
            const(TemplateArgumentDeclaration) argDecl = pair[0];
            const(TemplateArgumentInstance) argValue = pair[1];

            result.templateParameterList.items ~= [argDecl.buildWithSpecialization(argValue)];
        }

        return result;
    }

    override pure
    dparse.ast.Type buildConcreteType() const
    {
        assert(0);
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }

    override pure
    dparse.ast.IdentifierOrTemplateInstance unqualifiedName() const
    {
        auto inst = new dparse.ast.TemplateInstance();
        inst.identifier = tokenFromString(name);
        inst.templateArguments = templateArgumentValues.buildConcreteList();

        auto result = new dparse.ast.IdentifierOrTemplateInstance();
        result.templateInstance = inst;

        return result;
    }
}

// TODO dedup with SpecializedStructDeclaration
class SpecializedInterfaceDeclaration : InterfaceDeclaration
{
    TemplateArgumentInstanceList templateArgumentValues;

    bool shouldEmit_ = true;

    override pure
    bool shouldEmit() const
    {
        return shouldEmit_;
    }

    protected override
    dparse.ast.TemplateParameters buildTemplateList() const
    {
        import std.range : zip;

        assert(!templateArguments.args.isNull);
        assert(!templateArgumentValues.arguments.isNull);

        auto result = new dparse.ast.TemplateParameters();
        result.templateParameterList = new dparse.ast.TemplateParameterList();
        foreach (pair; zip(templateArguments.args.get(), templateArgumentValues.arguments.get()))
        {
            const(TemplateArgumentDeclaration) argDecl = pair[0];
            const(TemplateArgumentInstance) argValue = pair[1];

            result.templateParameterList.items ~= [argDecl.buildWithSpecialization(argValue)];
        }

        return result;
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
    dparse.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

// Maybe these shouldn't be declarations?  We need the "declaration" to be a
// dparse.ast.TemplateParameter, so I've added a method here.  But now the
// Declaration part of this type isn't used anymore.
class TemplateArgumentDeclaration : Declaration
{
    pure abstract
    dparse.ast.TemplateParameter buildTemplateParameter() const;

    pure abstract
    dparse.ast.TemplateParameter buildWithSpecialization(const(TemplateArgumentInstance) value) const;

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class TemplateTypeArgumentDeclaration : TemplateArgumentDeclaration, Type
{
    Type defaultType;

    override pure
    dparse.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    mixin .buildConcreteType!();

    override pure
    dparse.ast.TemplateParameter buildTemplateParameter() const
    {
        auto result = new dparse.ast.TemplateParameter();
        result.templateTypeParameter = new dparse.ast.TemplateTypeParameter();
        // TODO deal with default types, specific specializations, etc.
        result.templateTypeParameter.identifier = tokenFromString(name);

        if (defaultType !is null)
        {
            result.templateTypeParameter.assignType = defaultType.buildConcreteType();
        }

        return result;
    }

    override pure
    dparse.ast.TemplateParameter buildWithSpecialization(const(TemplateArgumentInstance) unsafeValue) const
    {
        const TemplateTypeArgumentInstance value = cast(TemplateTypeArgumentInstance)unsafeValue;
        if (!value)
        {
            throw new Exception("Value for the specialization of a template type argument was not a type.");
        }

        auto result = new dparse.ast.TemplateParameter();
        result.templateTypeParameter = new dparse.ast.TemplateTypeParameter();
        result.templateTypeParameter.identifier = tokenFromString(name);
        result.templateTypeParameter.colonType = value.type.buildConcreteType();
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
    dparse.ast.Declaration buildConcreteDecl() const
    {
        assert(0);
    }

    override pure
    dparse.ast.TemplateParameter buildTemplateParameter() const
    {
        auto result = new dparse.ast.TemplateParameter();
        result.templateValueParameter = new dparse.ast.TemplateValueParameter();
        result.templateValueParameter.type = type.buildConcreteType();
        result.templateValueParameter.identifier = tokenFromString(name);
        // TODO deal with defaultValue

        if (defaultValue !is null)
        {
            auto default_ = new dparse.ast.TemplateValueParameterDefault();
            default_.assignExpression = defaultValue.buildConcreteExpression();
            result.templateValueParameter.templateValueParameterDefault = default_;
        }

        return result;
    }

    override pure
    dparse.ast.TemplateParameter buildWithSpecialization(const(TemplateArgumentInstance) unsafeValue) const
    {
        const value = cast(TemplateValueArgumentInstance)unsafeValue;
        if (!value)
        {
            throw new Exception("Value for the specialization of a template value argument was not a value.");
        }

        auto result = new dparse.ast.TemplateParameter();
        result.templateValueParameter = new dparse.ast.TemplateValueParameter();
        result.templateValueParameter.type = type.buildConcreteType();
        result.templateValueParameter.identifier = tokenFromString(name);
        result.templateValueParameter.assignExpression = value.exp.buildConcreteExpression();
        return result;
    }


    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new dparse.ast.PrimaryExpression();
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

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        dparse.ast.FunctionDeclaration methodDecl;
        dparse.ast.Declaration result = FunctionDeclaration.buildConcreteDecl(&methodDecl);
        assert(methodDecl !is null);
        if (const_)
        {
            auto attr = new dparse.ast.MemberFunctionAttribute();
            attr.tokenType = tok!"const";
            methodDecl.memberFunctionAttributes ~= [attr];
        }

        addVisibility(result);

        if (!virtual_)
        {
            auto attr = new dparse.ast.Attribute();
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
    // TODO should find a way to restrict this to interface types
    Type[] bases;

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

    void addDeclarations(Declaration[] ds)
    {
        foreach (d; ds)
        {
            addDeclaration(d);
        }
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
        bases ~= [b];
        // TODO emit them, check that they are interfaces and gracefully handle
        // the failure case (it could be a replaced type that is the interface)
    }

    protected dparse.ast.TemplateParameters buildTemplateList() const
    {
        return templateArguments.buildConcreteList();
    }

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        auto result = new dparse.ast.Declaration();
        auto interfaceDecl = new dparse.ast.InterfaceDeclaration();
        result.interfaceDeclaration = interfaceDecl;

        interfaceDecl.name = tokenFromString(name);
        interfaceDecl.templateParameters = buildTemplateList();

        auto body_ = new dparse.ast.StructBody();

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

    void addDeclarations(Declaration[] ds)
    {
        foreach (d; ds)
        {
            addDeclaration(d);
        }
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

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        auto result = new dparse.ast.Declaration();
        auto unionDecl = new dparse.ast.UnionDeclaration();
        result.unionDeclaration = unionDecl;

        if (name.length)
        {
            unionDecl.name = tokenFromString(name);
        }

        unionDecl.templateParameters = templateArguments.buildConcreteList();

        unionDecl.structBody = new dparse.ast.StructBody();

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
    dparse.ast.Type buildConcreteType() const
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

    override
    dparse.ast.Declaration buildConcreteDecl() const
    {
        auto result = new dparse.ast.Declaration();
        auto aliasDecl = new dparse.ast.AliasDeclaration();
        result.aliasDeclaration = aliasDecl;

        auto initializer = new dparse.ast.AliasInitializer();
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
