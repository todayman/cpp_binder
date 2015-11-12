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

import std.typecons : Flag, No;

import std.d.ast : IdentifierOrTemplateChain;

class Declaration
{
    Declaration parent;
    // Do all declarations have visibility?
    Visibility visibility;

    string name;
}

class Namespace : Declaration
{
    Declaration[] declarations;
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
