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

import std.d.ast;
import std.d.lexer;

static import binder;
static import unknown;

import translate.decls : determineRecordStrategy;

public std.d.ast.Type[unknown.Type*] translated_types;
private std.d.ast.Type[string] types_by_name;
private std.d.ast.Type[void*] typeForDecl;

void determineStrategy(unknown.Type* cppType)
{
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
    }
}

std.d.ast.Type replaceType(unknown.Type* cppType)
{
    std.d.ast.Type result;
    string replacement_name = binder.toDString(cppType.getReplacement());
    if (replacement_name.length > 0)
    {
        if (replacement_name !in types_by_name)
        {
            result = new std.d.ast.Type();
            types_by_name[replacement_name] = result;
            result.type2 = new Type2();
            result.type2.symbol = new Symbol();
            result.type2.symbol.identifierOrTemplateChain = makeIdentifierOrTemplateChain(replacement_name);

            // FIXME Which package / module do these go in?
        }
        else
        {
            // FIXME do this without the second lookup
            result = types_by_name[replacement_name];
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
                    result = translatePointer(cppType);
                case unknown.Type.Kind.Reference:
                    result = translateReference(cppType);
                case unknown.Type.Kind.Typedef:
                    result = replaceTypedef(cppType);
                case unknown.Type.Kind.Enum:
                    result = replaceEnum(cppType);
                case unknown.Type.Kind.Function:
                    result = replaceFunction(cppType);

                case unknown.Type.Kind.Record:
                    // TODO figure out (again) why this is an error and add
                    // a comment explaining that
                    throw new Error("Called replaceType on a Record");
                    break;
                case unknown.Type.Kind.Union:
                    result = replaceUnion(cppType);
                    break;
                case unknown.Type.Kind.Array:
                    // TODO
                    throw new Error("replaceType on Arrays is not implemented yet.");
                    break;
                case unknown.Type.Kind.Vector:
                    throw new Error("replaceType on Vector types is not implemented yet.");
                    break;
            }
            translated_types[cppType] = result;
        }
    }
    return result;
}

// FIXME need to preserve pointer/refness
// FIXME D ref isn't a type constructor, it's a storage class, so this doesn't really work anymore
// ref is applied to the argument declaration, not the type
std.d.ast.Type translatePointerOrReference(unknown.Type* cppType)
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
        result = translateType(target_type);
    }
    else
    {
        // FIXME assuming pointer here, and not reference
        result = new std.d.ast.Type();
        TypeSuffix pointerSuffix = new TypeSuffix();
        pointerSuffix.star = true;
        result.typeSuffixes = [pointerSuffix];
        result.type2 = translateType2(target_type);
    }

    return result;
}

private std.d.ast.Type translatePointer(unknown.Type* cppType)
{
    return translatePointerOrReference(cppType);
}
private std.d.ast.Type translateReference(unknown.Type* cppType)
{
    return translatePointerOrReference(cppType);
}

// FIXME add a method on the Type struct that just gets the declaration,
// so this template can turn into a normal function
private string replaceMixin(string SourceType, string TargetType)() {
    return "
private std.d.ast.Type replace" ~ TargetType ~ "(unknown.Type* cppType)
{
    unknown." ~ SourceType ~ "Declaration cppDecl = cppType.get" ~ SourceType ~ "Declaration();
    try {
        return typeForDecl[cast(void*)cppDecl];
    }
    catch (RangeError e)
    {
        std.d.ast.Type result = new std.d.ast.Type();
        // TODO fill in the type?
        // Actually, I think that will happen when I traverse the declaration
        typeForDecl[cast(void*)cppDecl] = result;
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

private std.d.ast.Type replaceFunction(unknown.Type*)
{
    // Needed for translating function types, but not declarations,
    // so I'm putting it off until later
    throw new Error("Translation of function types is not implemented yet.");
}

std.d.ast.Type translateType(unknown.Type* cppType)
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
                result = translateType(cppType);
                break;
            case unknown.Strategy.REPLACE:
                result = replaceType(cppType);
                break;
            case unknown.Strategy.STRUCT:
                result = replaceStruct(cppType);
                break;
            case unknown.Strategy.INTERFACE:
                result = replaceInterface(cppType);
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

std.d.ast.Type2 translateType2(unknown.Type* cppType)
{
    std.d.ast.Type type = translateType(cppType);
    return type.type2;
}
