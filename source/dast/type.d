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

static import std.d.ast;
import std.d.lexer : tok, Token;

import dast.decls : Argument;
import dast.expr : Expression;

public interface Type
{
    pure std.d.ast.Type buildConcreteType() const;
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
        result.type2.type = target.buildConcreteType();

        return result;
    }
}

// A specific value of a template argument
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
        auto result = targetType.buildConcreteType();

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
    Argument[] arguments; // They just won't have names

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        auto result = returnType.buildConcreteType();
        auto suffix = new std.d.ast.TypeSuffix();
        suffix.delegateOrFunction = Token(tok!"function", "", 0, 0, 0);
        suffix.parameters = new std.d.ast.Parameters();
        suffix.parameters.parameters = arguments.map!(a => a.buildConcreteArgument()).array;
        result.typeSuffixes ~= [suffix];

        // TODO varargs
        return result;
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
        result.type2.symbol.identifierOrTemplateChain = fullyQualifiedName.deepDup();
        return result;
    }
}

class SpecializedStructType : Type
{
    // FIXME change to StructDeclaration
    dast.decls.StructDeclaration genericParent;

    TemplateArgument[] arguments;

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
    }
}
class SpecializedInterfaceType : Type
{
    // FIXME change to StructDeclaration
    dast.decls.Declaration genericParent;

    TemplateArgument[] arguments;

    override pure
    std.d.ast.Type buildConcreteType() const
    {
        assert(0);
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
    if (src is null)
    {
        return null;
    }
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
