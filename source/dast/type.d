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

module dast.type;

import std.algorithm : map;
import std.array : array;

static import dparse.ast;
import dparse.lexer : tok, Token;

import dast.decls : Argument;
import dast.expr : Expression;

public interface Type
{
    pure dparse.ast.Type buildConcreteType() const;

    pure string typestring() const;
}

class ConstType : Type
{
    Type target;

    this(Type t)
    {
        target = t;
    }

    override pure
    dparse.ast.Type buildConcreteType() const
    {
        auto result = new dparse.ast.Type();
        result.type2 = new dparse.ast.Type2();
        result.type2.typeConstructor = tok!"const";
        result.type2.type = target.buildConcreteType();

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
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
    dparse.ast.Type buildConcreteType() const
    {
        auto result = targetType.buildConcreteType();

        auto starSuffix = new dparse.ast.TypeSuffix();
        starSuffix.star = Token(tok!"*", "", 0, 0, 0);
        result.typeSuffixes ~= [starSuffix];

        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class FunctionType : Type
{
    Type returnType;

    bool varargs;
    Argument[] arguments; // They just won't have names

    override pure
    dparse.ast.Type buildConcreteType() const
    {
        auto result = returnType.buildConcreteType();
        auto suffix = new dparse.ast.TypeSuffix();
        suffix.delegateOrFunction = Token(tok!"function", "", 0, 0, 0);
        suffix.parameters = new dparse.ast.Parameters();
        suffix.parameters.parameters = arguments.map!(a => a.buildConcreteArgument()).array;
        result.typeSuffixes ~= [suffix];

        // TODO varargs
        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

class ArrayType : Type
{
    Type elementType;
    Expression length;

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

// A type that we have been instructed to replace with a specific name
class ReplacedType : Type
{
    // TODO do I really want to be using this type?
    dparse.ast.IdentifierOrTemplateChain fullyQualifiedName;

    override pure
    dparse.ast.Type buildConcreteType() const
    {
        auto result = new dparse.ast.Type();
        result.type2 = new dparse.ast.Type2();
        result.type2.symbol = new dparse.ast.Symbol();
        result.type2.symbol.dot = false; // TODO maybe it shouldn't always be?
        result.type2.symbol.identifierOrTemplateChain = new dparse.ast.IdentifierOrTemplateChain();
        // FIXME why do I need the template argument on dup?
        result.type2.symbol.identifierOrTemplateChain = fullyQualifiedName.deepDup();
        return result;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}

// Maybe this should get rolled into SpecializedStructDeclaration?
class SpecializedStructType : Type
{
    dast.decls.StructDeclaration genericParent;

    dast.decls.TemplateArgumentInstanceList arguments;

    override pure
    dparse.ast.Type buildConcreteType() const
    {
        auto inst = new dparse.ast.TemplateInstance();
        inst.templateArguments = arguments.buildConcreteList();

        dparse.ast.Type genericType = genericParent.buildConcreteType();
        assert(genericType.type2 !is null);
        assert(genericType.type2.symbol !is null);
        assert(genericType.type2.symbol.identifierOrTemplateChain !is null);

        dparse.ast.IdentifierOrTemplateInstance lastLink
            = genericType.type2.symbol.identifierOrTemplateChain.identifiersOrTemplateInstances[$-1];
        assert(lastLink.templateInstance is null);
        inst.identifier = lastLink.identifier;
        lastLink.identifier = Token.init;
        lastLink.templateInstance = inst;

        return genericType;
    }

    override pure string typestring() const
    {
        return typeof(this).stringof;
    }
}
class SpecializedInterfaceType : Type
{
    // FIXME change to InterfaceDeclaration
    dast.decls.Declaration genericParent;

    dast.decls.TemplateArgumentInstanceList arguments;

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

// Used in the body of a template to refer to a type that is a parameter of the
// template.  Paul thinks.  Maybe...
class TemplateArgumentType : Type
{
    string name;

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

dparse.ast.Type deepDup(const(dparse.ast.Type) src) pure
{
    if (src is null)
    {
        return null;
    }

    auto result = new dparse.ast.Type();
    result.typeConstructors = src.typeConstructors.dup;
    result.typeSuffixes = src.typeSuffixes.map!(deepDup).array;
    result.type2 = deepDup(src.type2);
    return result;
}

dparse.ast.TypeSuffix deepDup(const(dparse.ast.TypeSuffix) src) pure
{
    auto result = new dparse.ast.TypeSuffix();
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

dparse.ast.Type2 deepDup(const(dparse.ast.Type2) src) pure
{
    auto result = new dparse.ast.Type2();
    result.builtinType = src.builtinType;
    result.symbol = deepDup(src.symbol);
    assert(src.typeofExpression is null);
    result.identifierOrTemplateChain = deepDup(src.identifierOrTemplateChain);
    result.typeConstructor = src.typeConstructor;
    result.type = deepDup(src.type);
    assert(src.vector is null);

    return result;
}

dparse.ast.Symbol deepDup(const(dparse.ast.Symbol) src) pure
{
    if (src is null)
    {
        return null;
    }
    auto result = new dparse.ast.Symbol();
    result.identifierOrTemplateChain = deepDup(src.identifierOrTemplateChain);
    result.dot = src.dot;
    return result;
}

dparse.ast.IdentifierOrTemplateChain deepDup(const(dparse.ast.IdentifierOrTemplateChain) src) pure
{
    if (src is null)
    {
        return null;
    }

    auto result = new dparse.ast.IdentifierOrTemplateChain();
    result.identifiersOrTemplateInstances = deepDup(src.identifiersOrTemplateInstances);
    return result;
}

dparse.ast.IdentifierOrTemplateInstance[] deepDup(const(dparse.ast.IdentifierOrTemplateInstance)[] arr) pure
{
    auto result = new dparse.ast.IdentifierOrTemplateInstance[arr.length];
    foreach (index, const a; arr)
    {
        result[index] = new dparse.ast.IdentifierOrTemplateInstance();
        result[index].identifier = a.identifier;
        if (a.templateInstance)
        {
            result[index].templateInstance = deepDup(a.templateInstance);
        }
    }

    return result;
}

dparse.ast.TemplateInstance deepDup(const(dparse.ast.TemplateInstance) src) pure
{
    auto result = new dparse.ast.TemplateInstance();
    result.identifier = src.identifier;
    result.templateArguments = deepDup(src.templateArguments);
    return result;
}

dparse.ast.TemplateArguments deepDup(const(dparse.ast.TemplateArguments) src) pure
{
    auto result = new dparse.ast.TemplateArguments();
    result.templateArgumentList = deepDup(src.templateArgumentList);
    result.templateSingleArgument = deepDup(src.templateSingleArgument);
    return result;
}

dparse.ast.TemplateArgumentList deepDup(const(dparse.ast.TemplateArgumentList) src) pure
{
    auto result = new dparse.ast.TemplateArgumentList();
    result.items = new dparse.ast.TemplateArgument[src.items.length];
    foreach (index, const item; src.items)
    {
        result.items[index] = deepDup(item);
    }
    return result;
}

dparse.ast.TemplateArgument deepDup(const(dparse.ast.TemplateArgument) src) pure
{
    auto result = new dparse.ast.TemplateArgument();
    result.type = null; // TODO fill in
    result.assignExpression = null; // TODO fill in
    return result;
}

dparse.ast.TemplateSingleArgument deepDup(const(dparse.ast.TemplateSingleArgument) src) pure
{
    auto result = new dparse.ast.TemplateSingleArgument();
    result.token = src.token;
    return result;
}
