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

module translate.types;

import core.exception : RangeError;

import std.conv : to;
import std.stdio : stderr;
import std.typecons : Flag;

import std.d.ast;
import std.d.lexer;

static import binder;
static import unknown;

import dlang_decls : concat, makeIdentifierOrTemplateChain;

private std.d.ast.Type[unknown.Type*] translated_types;
private std.d.ast.Type[string] types_by_name;
private std.d.ast.Symbol[void*] symbolForDecl;
package unknown.Declaration[std.d.ast.Symbol] unresolvedSymbols;
package string [const std.d.ast.Symbol] symbolModules;

package void determineStrategy(unknown.Type* cppType)
{
    import translate.decls : determineRecordStrategy;

    if (cppType.getStrategy() != unknown.Strategy.UNKNOWN)
    {
        return;
    }

    final switch (cppType.getKind())
    {
        case unknown.Type.Kind.Invalid:
            cppType.dump();
            throw new Exception("Attempting to determine strategy for invalid type.");
            break;
        case unknown.Type.Kind.Builtin:
            stderr.write("I don't know how to translate the builtin C++ type:\n");
            cppType.dump();
            stderr.write("\n");
            throw new Exception("Cannot translate builtin.");
            break;
        case unknown.Type.Kind.Pointer:
        case unknown.Type.Kind.Reference:
        case unknown.Type.Kind.Typedef:
        case unknown.Type.Kind.Enum:
        case unknown.Type.Kind.Function:
            // FIXME empty string means resolve to an actual AST type, not a string
            cppType.chooseReplaceStrategy(binder.toBinderString(""));
            break;

        case unknown.Type.Kind.Record:
            determineRecordStrategy(cppType);
            break;
        case unknown.Type.Kind.Union:
            cppType.chooseReplaceStrategy(binder.toBinderString("")); // FIXME see note for Function
            break;
        case unknown.Type.Kind.Array:
            break;
        case unknown.Type.Kind.Vector:
            throw new Error("Cannot translate vector (e.g. SSE, AVX) types.");
        case unknown.Type.Kind.Qualified:
            determineStrategy(cppType.unqualifiedType());
            cppType.chooseReplaceStrategy(binder.toBinderString(""));
            break;
    }
}

struct QualifierSet
{
    bool const_ = false;
}

private std.d.ast.Type replaceType(unknown.Type* cppType, QualifierSet qualifiers)
{
    std.d.ast.Type result;
    string replacement_name = binder.toDString(cppType.getReplacement());
    if (replacement_name.length > 0)
    {
        try {
            result = types_by_name[replacement_name];
        }
        catch (RangeError e)
        {
            result = new std.d.ast.Type();
            types_by_name[replacement_name] = result;
            result.type2 = new Type2();
            result.type2.symbol = new Symbol();
            result.type2.symbol.identifierOrTemplateChain = makeIdentifierOrTemplateChain!"."(replacement_name);

            unknown.Declaration decl = cppType.getDeclaration();
            if (decl !is null)
            {
                symbolModules[result.type2.symbol] = binder.toDString(decl.getTargetModule());
            }
            else
            {
                auto target_module = cppType.getReplacementModule();
                if (target_module !is null && target_module.size > 0)
                {
                    symbolModules[result.type2.symbol] = binder.toDString(target_module);
                }
            }
        }

        return result;
    }
    else
    {
        try {
            return translated_types[cppType];
        }
        catch (RangeError e)
        {
            final switch (cppType.getKind())
            {
                case unknown.Type.Kind.Invalid:
                    throw new Error("Attempting to translate an Invalid type");
                    break;
                case unknown.Type.Kind.Builtin:
                    // TODO figure out (again) why this is an error and add
                    // a comment explaining that
                    throw new Error("Called replaceType on a Builtin");
                    break;
                case unknown.Type.Kind.Pointer:
                    result = translatePointer(cppType, qualifiers);
                    break;
                case unknown.Type.Kind.Reference:
                    result = translateReference(cppType, qualifiers);
                    break;
                case unknown.Type.Kind.Typedef:
                    result = translate!"Typedef"(cppType, qualifiers);
                    break;
                case unknown.Type.Kind.Enum:
                    result = translate!"Enum"(cppType, qualifiers);
                    break;
                case unknown.Type.Kind.Function:
                    result = replaceFunction(cppType, qualifiers);
                    break;

                case unknown.Type.Kind.Record:
                    // TODO figure out (again) why this is an error and add
                    // a comment explaining that
                    throw new Error("Called replaceType on a Record");
                    break;
                case unknown.Type.Kind.Union:
                    result = translate!"Union"(cppType, qualifiers);
                    break;
                case unknown.Type.Kind.Array:
                    // TODO
                    throw new Error("replaceType on Arrays is not implemented yet.");
                    break;
                case unknown.Type.Kind.Vector:
                    throw new Error("replaceType on Vector types is not implemented yet.");
                    break;
                case unknown.Type.Kind.Qualified:
                    result = translate!"Qualified"(cppType, qualifiers);
                    break;
            }
            translated_types[cppType] = result;
        }
    }
    return result;
}

class RefTypeException : Exception
{
    public:
    unknown.Type * type;
    this(unknown.Type * t)
    {
        super("Trying to translate into a ref");
        type = t;
    }
};

private std.d.ast.Type translatePointerOrReference
    (Flag!"ref" ref_)
    (unknown.Type* cppType, QualifierSet qualifiers)
{
    unknown.Type* target_type = cppType.getPointeeType();
    // If a strategy is already picked, then this returns immediately
    determineStrategy(target_type);
    bool target_is_reference_type = false;
    switch (target_type.getStrategy())
    {
        case unknown.Strategy.UNKNOWN:
            throw new Error("Attempted to determine the translation strategy for a pointer or referenced decided on UNKNOWN.");
        case unknown.Strategy.REPLACE:
        case unknown.Strategy.STRUCT:
            target_is_reference_type = false;
            break;
        case unknown.Strategy.INTERFACE:
        case unknown.Strategy.CLASS:
        case unknown.Strategy.OPAQUE_CLASS:
            target_is_reference_type = true;
            break;
        default:
            throw new Error("I don't know what strategy was selected for a pointer or reference type.");
    }

    std.d.ast.Type result;
    if (target_is_reference_type)
    {
        result = translateType(target_type, qualifiers);
    }
    else
    {
        static if (ref_)
        {
            // Since D refs aren't allowed everywhere, indicate that cppType is
            // a ref, causing us to look higher up in the call stack where we
            // can tell if this is an allowed place for a ref.
            // If it is allowed, then the caller will deal with the ref and
            // translate the un-ref-ed type.
            throw new RefTypeException(cppType);
        }
        else
        {
            result = new std.d.ast.Type();
            TypeSuffix pointerSuffix = new TypeSuffix();
            pointerSuffix.star = Token(tok!"*", "", 0, 0, 0);
            result.typeSuffixes = [pointerSuffix];

            std.d.ast.Type translatedTargetType = translateType(target_type, qualifiers).clone;
            if (translatedTargetType.typeConstructors.length > 0)
            {
                result.type2 = new Type2();
                result.type2.typeConstructor = translatedTargetType.typeConstructors[0];
                translatedTargetType.typeConstructors = translatedTargetType.typeConstructors[1 .. $];
                result.type2.type = translatedTargetType;
            }
            else
            {
                // FIXME potentially does many concatenations; there should be a way
                // to build them all into the same array.
                // But this probably won't be a real problem, because
                // how deep do people's types actually go? (Don't answer that!)
                result.typeSuffixes ~= translatedTargetType.typeSuffixes;
                result.type2 = translatedTargetType.type2;
            }
        }
    }

    return result;
}

private std.d.ast.Type translatePointer(unknown.Type* cppType, QualifierSet qualifiers)
{
    return translatePointerOrReference!(Flag!"ref".no)(cppType, qualifiers);
}
private std.d.ast.Type translateReference(unknown.Type* cppType, QualifierSet qualifiers)
{
    return translatePointerOrReference!(Flag!"ref".yes)(cppType, qualifiers);
}

// FIXME add a method on the Type struct that just gets the declaration,
// so this template can turn into a normal function
private string replaceMixin(string SourceType, string TargetType)() {
    return "
private std.d.ast.Symbol resolveOrDefer" ~ TargetType ~ "Symbol(unknown.Type* cppType)
{
    unknown." ~ SourceType ~ "Declaration cppDecl = cppType.get" ~ SourceType ~ "Declaration();
    try {
        return symbolForDecl[cast(void*)cppDecl];
    }
    catch (RangeError e)
    {
        std.d.ast.Symbol result = null;
        if (cppDecl !is null)
        {
            result = new std.d.ast.Symbol();
            // This symbol will be filled in when the declaration is traversed
            symbolForDecl[cast(void*)cppDecl] = result;
            unresolvedSymbols[result] = cppDecl;
        }
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        return result;
    }
}";
}
// TODO Before I made this into a mixin, these checked the kinds of the types
// passed in to make sure that the correct function was being called.  I.e.
// check that cppType was a union, enum, etc.
mixin (replaceMixin!("Typedef", "Typedef"));
mixin (replaceMixin!("Enum", "Enum"));
mixin (replaceMixin!("Union", "Union"));
mixin (replaceMixin!("Record", "Struct"));
mixin (replaceMixin!("Record", "Interface"));

private std.d.ast.Type translate(string kind)(unknown.Type* cppType, QualifierSet qualifiers)
{
    auto result = new std.d.ast.Type();
    auto type2 = new std.d.ast.Type2();
    result.type2 = type2;
    type2.symbol = mixin("resolveOrDefer"~kind~"Symbol(cppType)");
    return result;
}

// I tried to call this dup, but then I couldn't use dup on the inside
std.d.ast.Type clone(std.d.ast.Type t)
{
    auto result = new std.d.ast.Type();
    if (t.typeConstructors !is null) result.typeConstructors = t.typeConstructors.dup;
    if (t.typeSuffixes !is null) result.typeSuffixes = t.typeSuffixes.dup;
    result.type2 = t.type2;
    return result;
}

private std.d.ast.Type translate(string kind : "Qualified")
    (unknown.Type* cppType, QualifierSet qualifiersAlreadApplied)
{
    QualifierSet innerQualifiers;
    if (cppType.isConst() || qualifiersAlreadApplied.const_)
    {
        innerQualifiers.const_ = true;
    }
    std.d.ast.Type result = translateType(cppType.unqualifiedType(), innerQualifiers).clone;

    // Apply qualifiers that 
    if (cppType.isConst() && !qualifiersAlreadApplied.const_)
    {
        result.typeConstructors ~= [tok!"const"];
    }

    return result;
}

private std.d.ast.Type replaceFunction(unknown.Type*, QualifierSet)
{
    // Needed for translating function types, but not declarations,
    // so I'm putting it off until later
    throw new Error("Translation of function types is not implemented yet.");
}

// Qualifiers are the qualifiers that have already been applied to the type.
// e.g. when const(int*) does the const * part then calls translateType(int, const)
// So that const is not applied transitively all the way down
public std.d.ast.Type translateType(unknown.Type* cppType, QualifierSet qualifiers)
{
    if (cppType in translated_types)
    {
        return translated_types[cppType];
    }
    else
    {
        std.d.ast.Type result;
        final switch (cppType.getStrategy())
        {
            case unknown.Strategy.UNKNOWN:
                determineStrategy(cppType);
                result = translateType(cppType, qualifiers);
                break;
            case unknown.Strategy.REPLACE:
                result = replaceType(cppType, qualifiers);
                break;
            case unknown.Strategy.STRUCT:
                result = translate!"Struct"(cppType, qualifiers);
                break;
            case unknown.Strategy.INTERFACE:
                // TODO I should check what the code paths into here are,
                // because you shouldn't translate to interfaces directly,
                // you should translate a pointer or ref to an interface into
                // an interface
                result = translate!"Interface"(cppType, qualifiers);
                break;
            case unknown.Strategy.CLASS:
                break;
            case unknown.Strategy.OPAQUE_CLASS:
                break;
        }

        if (result !is null)
        {
            translated_types[cppType] = result;
        }
        else
        {
            throw new Exception("Cannot translate type with strategy " ~ to!string(cppType.getStrategy()));
        }
        return result;
    }
}

package void makeSymbolForDecl(SourceDeclaration)(SourceDeclaration cppDecl, Token targetName, IdentifierChain package_name, IdentifierOrTemplateChain internal_path, string namespace_path)
{
    import std.array : join;
    import std.algorithm : map;
    import dlang_decls : append;

    std.d.ast.Symbol symbol;
    try {
        symbol = symbolForDecl[cast(void*)cppDecl];
        // Since the symbol is already in the table, this means
        // that it was used unresolved in a type somewhere.
        // We're resolving it right here, right now.
        unresolvedSymbols.remove(symbol);
    }
    catch (RangeError e)
    {
        symbol = new std.d.ast.Symbol();
        symbolForDecl[cast(void*)cppDecl] = symbol;
    }

    IdentifierOrTemplateChain chain = concat(package_name, internal_path);
    auto namespace_chain = makeIdentifierOrTemplateChain!"::"(namespace_path);
    chain = chain.concat(namespace_chain);
    chain.append(targetName);
    symbol.identifierOrTemplateChain = chain;

    if (package_name.identifiers.length > 0)
    {
        symbolModules[symbol] = join(package_name.identifiers.map!(a => a.text), ".");
    }
}
