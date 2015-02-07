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

private std.d.ast.Type[void*] translated_types;
private std.d.ast.Type[string] types_by_name;
package std.d.ast.Symbol[void*] symbolForType;
package unknown.Declaration[std.d.ast.Symbol] unresolvedSymbols;
package string [const std.d.ast.Symbol] symbolModules;
package DeferredTemplateInstantiation[const std.d.ast.Symbol] deferredTemplates;

package void determineStrategy(unknown.Type cppType)
{
    import translate.decls : determineRecordStrategy;

    if (cppType.getStrategy() != unknown.Strategy.UNKNOWN)
    {
        return;
    }

    class StrategyChoiceVisitor : unknown.TypeVisitor
    {
        public:
        override extern(C++) void visit(unknown.InvalidType cppType)
        {
            cppType.dump();
            throw new Exception("Attempting to determine strategy for invalid type.");
        }

        override extern(C++) void visit(unknown.BuiltinType cppType)
        {
            stderr.write("I don't know how to translate the builtin C++ type:\n");
            cppType.dump();
            stderr.write("\n");
            throw new Exception("Cannot translate builtin.");
        }

        mixin template Replace(T) {
            // TODO turn this into a template?
            override extern(C++) void visit(T cppType)
            {
                // FIXME empty string means resolve to an actual AST type, not a string
                cppType.chooseReplaceStrategy(binder.toBinderString(""));
            }
        }
        mixin Replace!(unknown.PointerType);
        mixin Replace!(unknown.ReferenceType);
        mixin Replace!(unknown.TypedefType);
        mixin Replace!(unknown.EnumType);
        mixin Replace!(unknown.FunctionType);
        mixin Replace!(unknown.TemplateArgumentType);
        mixin Replace!(unknown.UnionType);

        override extern(C++) void visit(unknown.NonTemplateRecordType cppType)
        {
            determineRecordStrategy(cppType);
        }
        override extern(C++) void visit(unknown.TemplateRecordType cppType)
        {
            determineRecordStrategy(cppType);
        }

        override extern(C++) void visit(unknown.ArrayType cppType)
        {
            // TODO not implemented yet
            throw new Error("Don't know how to choose a strategy for Array types. Implement me!");
        }

        override extern(C++) void visit(unknown.VectorType cppType)
        {
            throw new Error("Cannot translate vector (e.g. SSE, AVX) types.");
        }

        override extern(C++) void visit(unknown.QualifiedType cppType)
        {
            determineStrategy(cppType.unqualifiedType());
            cppType.chooseReplaceStrategy(binder.toBinderString(""));
        }

        override extern(C++) void visit(unknown.TemplateSpecializationType cppType)
        {
            unknown.Type generic_type = cppType.getTemplateDeclaration().getType();
            determineStrategy(generic_type);
            if (generic_type.getStrategy() == unknown.Strategy.REPLACE)
            {
                cppType.chooseReplaceStrategy(binder.toBinderString(""));
            }
            else
            {
                cppType.setStrategy(generic_type.getStrategy());
            }
        }

        override extern(C++) void visit(unknown.DelayedType cppType)
        {
            cppType.resolveType();
        }
    }

    auto visitor = new StrategyChoiceVisitor();
    cppType.visit(visitor);
}

struct QualifierSet
{
    bool const_ = false;
}

private std.d.ast.Type replaceType(unknown.Type cppType, QualifierSet qualifiers)
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
            return translated_types[cast(void*)cppType];
        }
        catch (RangeError e)
        {
            class TranslateTypeClass : unknown.TypeVisitor
            {
                public std.d.ast.Type result;
                extern(C++) void visit(unknown.InvalidType)
                {
                    throw new Error("Attempting to translate an Invalid type");
                }

                extern(C++) void visit(unknown.BuiltinType type)
                {
                    // TODO figure out (again) why this is an error and add
                    // a comment explaining that
                    throw new Error("Called replaceType on a Builtin");
                }

                extern(C++) void visit(unknown.PointerType cppType)
                {
                    result = translatePointer(cppType, qualifiers);
                }

                extern(C++) void visit(unknown.ReferenceType cppType)
                {
                    result = translateReference(cppType, qualifiers);
                }

                mixin template Translate(T) {
                    override extern(C++) void visit(T cppType)
                    {
                        result = translate(cppType, qualifiers);
                    }
                }
                mixin Translate!(unknown.TypedefType);
                mixin Translate!(unknown.EnumType);
                mixin Translate!(unknown.UnionType);
                mixin Translate!(unknown.QualifiedType);
                mixin Translate!(unknown.TemplateArgumentType);

                extern(C++) void visit(unknown.FunctionType cppType)
                {
                    result = replaceFunction(cppType);
                }

                mixin Translate!(unknown.NonTemplateRecordType);
                mixin Translate!(unknown.TemplateRecordType);

                extern(C++) void visit(unknown.ArrayType cppType)
                {
                    // TODO
                    throw new Error("replaceType on Arrays is not implemented yet.");
                }

                extern(C++) void visit(unknown.VectorType cppType)
                {
                    throw new Error("replaceType on Vector types is not implemented yet.");
                }

                extern(C++) void visit(unknown.TemplateSpecializationType cppType)
                {
                    // TODO should change depending on strategy and type of the actual thing
                    // TODO redo this in the new visitor / typesafe context
                    // Before, it was always a struct
                    // result = translate!(unknown.RecordType)(cppType, qualifiers);
                    throw new Error("Attempting to translate a template specialization type");
                }

                extern(C++) void visit(unknown.DelayedType type)
                {
                }
            }
            auto visitor = new TranslateTypeClass();
            cppType.visit(visitor);
            result = visitor.result;
            translated_types[cast(void*)cppType] = result;
        }
    }
    return result;
}

class RefTypeException : Exception
{
    public:
    unknown.Type type;
    this(unknown.Type t)
    {
        super("Trying to translate into a ref");
        type = t;
    }
};

private std.d.ast.Type translatePointerOrReference
    (Flag!"ref" ref_)
    (unknown.PointerOrReferenceType cppType, QualifierSet qualifiers)
{
    unknown.Type target_type = cppType.getPointeeType();
    // If a strategy is already picked, then this returns immediately
    determineStrategy(target_type);

    std.d.ast.Type result;
    if (target_type.isReferenceType())
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

// TODO Fold these into the strategy visitor
private std.d.ast.Type translatePointer(unknown.PointerOrReferenceType cppType, QualifierSet qualifiers)
{
    return translatePointerOrReference!(Flag!"ref".no)(cppType, qualifiers);
}
private std.d.ast.Type translateReference(unknown.ReferenceType cppType, QualifierSet qualifiers)
{
    return translatePointerOrReference!(Flag!"ref".yes)(cppType, qualifiers);
}

// FIXME add a method on the Type struct that just gets the declaration,
// so this template can turn into a normal function
private string replaceMixin(string SourceType, string TargetType)() {
    return "
private std.d.ast.Symbol resolveOrDefer" ~ TargetType ~ "TypeSymbol(unknown." ~ SourceType ~ "Type cppType)
{
    try {
        return symbolForType[cast(void*)cppType];
    }
    catch (RangeError e)
    {
        unknown." ~ SourceType ~ "Declaration cppDecl = cppType.get" ~ SourceType ~ "Declaration();
        std.d.ast.Symbol result = null;
        if (cppDecl !is null)
        {
            result = new std.d.ast.Symbol();
            // This symbol will be filled in when the declaration is traversed
            symbolForType[cast(void*)cppType] = result;
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
mixin (replaceMixin!("Record", "Record"));

private std.d.ast.Symbol resolveOrDeferNonTemplateRecordTypeSymbol(unknown.NonTemplateRecordType cppType)
{
    try {
        return symbolForType[cast(void*)cppType];
    }
    catch (RangeError e)
    {
        unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();
        std.d.ast.Symbol result = null;
        if (cppDecl !is null)
        {
            result = new std.d.ast.Symbol();
            // This symbol will be filled in when the declaration is traversed
            symbolForType[cast(void*)cppType] = result;
            unresolvedSymbols[result] = cppDecl;
        }
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        return result;
    }
}
private std.d.ast.Symbol resolveOrDeferTemplateRecordTypeSymbol(unknown.TemplateRecordType cppType)
{
    try {
        return symbolForType[cast(void*)cppType];
    }
    catch (RangeError e)
    {
        unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();
        std.d.ast.Symbol result = null;
        if (cppDecl !is null)
        {
            result = new std.d.ast.Symbol();
            // This symbol will be filled in when the declaration is traversed
            symbolForType[cast(void*)cppType] = result;
            unresolvedSymbols[result] = cppDecl;
        }
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        return result;
    }
}

private std.d.ast.Symbol resolveTemplateSpecializationTypeSymbol(unknown.TemplateSpecializationType cppType)
{
    auto deferred = new DeferredTemplateInstantiation();
    deferredTemplates[deferred.answer] = deferred;
    // This is dangerously close to recursion
    // but it isn't because this is the generic template type, not us
    // (the instantiation)
    deferred.templateName = translateType(cppType.getTemplateDeclaration().getType(), QualifierSet.init).type2.symbol;
    assert(deferred.templateName !is null);
    deferred.arguments.length = cppType.getTemplateArgumentCount();
    uint idx = 0;
    for (auto iter = cppType.getTemplateArgumentBegin(),
            finish = cppType.getTemplateArgumentEnd();
            !iter.equals(finish);
            iter.advance(), ++idx )
    {
        deferred.arguments[idx] = translateType(iter.get(), QualifierSet.init);
    }
    symbolForType[cast(void*)cppType] = deferred.answer;
    return deferred.answer;
}

// TODO merge this in to the mixin
private std.d.ast.Symbol resolveOrDeferTemplateArgumentTypeSymbol(unknown.TemplateArgumentType cppType)
{
    try {
        return symbolForType[cast(void*)cppType];
    }
    catch (RangeError e)
    {
        unknown.TemplateTypeArgumentDeclaration cppDecl = cppType.getTemplateTypeArgumentDeclaration();
        std.d.ast.Symbol result = null;
        if (cppDecl !is null)
        {
            result = new std.d.ast.Symbol();
            string name = binder.toDString(cppDecl.getTargetName());
            result.identifierOrTemplateChain = makeIdentifierOrTemplateChain!"."(name);
            // This symbol will be filled in when the declaration is traversed
            symbolForType[cast(void*)cppType] = result;
            // Template arguments are always in the local scope, so they are
            // always resolved.  Don't put them into the unresolved set.
        }
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        return result;
    }
}

private std.d.ast.Type translate(Type)(Type cppType, QualifierSet qualifiers)
{
    auto result = new std.d.ast.Type();
    auto type2 = new std.d.ast.Type2();
    result.type2 = type2;
    enum kind = Type.stringof;
    type2.symbol = mixin("resolveOrDefer"~kind~"Symbol(cppType)");
    return result;
}

// Need this to determine whether to do templates or not
// There might be a better way to do this.
// This was translateInterface(string kind)(args), but that caused
// and ICE in dmd 2.066.1.  It does not ICE in dmd master
// (37e6395849fd762bcc1ec1ac036fff79db2d2693)
// FIXME collapse into template
private std.d.ast.Type translateInterface(unknown.Type cppType, QualifierSet qualifiers)
{
    auto result = new std.d.ast.Type();
    auto type2 = new std.d.ast.Type2();
    result.type2 = type2;

    class RecordTranslationVisitor : unknown.TypeVisitor
    {
        public std.d.ast.Symbol result;

        static private string Translate(string T) {
            return "override extern(C++) void visit(unknown."~T~"Type cppType)
            {
                throw new Error(\"Attempting to translate a "~T~" type as an interface.\");
            }";
        }
        mixin(Translate("Invalid"));
        mixin(Translate("Builtin"));
        mixin(Translate("Pointer"));
        mixin(Translate("Reference"));
        mixin(Translate("Typedef"));
        mixin(Translate("Enum"));
        mixin(Translate("Union"));
        mixin(Translate("Function"));
        mixin(Translate("Qualified"));
        mixin(Translate("TemplateArgument"));
        mixin(Translate("Array"));
        mixin(Translate("Vector"));

        override public extern(C++) void visit(unknown.NonTemplateRecordType cppType)
        {
            try {
                result = symbolForType[cast(void*)cppType];
            }
            catch (RangeError e)
            {
                unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();
                if (cppDecl !is null)
                {
                    result = new std.d.ast.Symbol();
                    // This symbol will be filled in when the declaration is traversed
                    symbolForType[cast(void*)cppType] = result;
                    unresolvedSymbols[result] = cppDecl;
                }
            }
        }

        // This needs to come up with a symbol that describes the template generally,
        // e.g. std::unordered_map, without template args
        override public extern(C++) void visit(unknown.TemplateRecordType cppType)
        {
            try {
                result = symbolForType[cast(void*)cppType];
            }
            catch (RangeError e)
            {
                unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();
                if (cppDecl !is null)
                {
                    result = new std.d.ast.Symbol();
                    // This symbol will be filled in when the declaration is traversed
                    symbolForType[cast(void*)cppType] = result;
                    unresolvedSymbols[result] = cppDecl;
                }
            }
        }

        override public extern(C++) void visit(unknown.TemplateSpecializationType cppType)
        {
            auto deferred = new DeferredTemplateInstantiation();
            deferredTemplates[deferred.answer] = deferred;
            // This is dangerously close to recursion
            // but it isn't because this is the generic template type, not us
            // (the instantiation)
            deferred.templateName = translateType(cppType.getTemplateDeclaration().getType(), QualifierSet.init).type2.symbol;
            assert(deferred.templateName !is null);
            deferred.arguments.length = cppType.getTemplateArgumentCount();
            uint idx = 0;
            for (auto iter = cppType.getTemplateArgumentBegin(),
                    finish = cppType.getTemplateArgumentEnd();
                    !iter.equals(finish);
                    iter.advance(), ++idx )
            {
                deferred.arguments[idx] = translateType(iter.get(), QualifierSet.init);
            }
            symbolForType[cast(void*)cppType] = deferred.answer;
            result = deferred.answer;
        }

        override public extern(C++) void visit(unknown.DelayedType cppType)
        {
            // TODO fill in!
        }
    }
    auto visitor = new RecordTranslationVisitor();
    cppType.visit(visitor);
    type2.symbol = visitor.result;
    return result;
}
private std.d.ast.Type translateStruct(unknown.Type cppType, QualifierSet qualifiers)
{
    auto result = new std.d.ast.Type();
    auto type2 = new std.d.ast.Type2();
    result.type2 = type2;

    class RecordTranslationVisitor : unknown.TypeVisitor
    {
        public std.d.ast.Symbol result;

        static private string Translate(string T) {
            return "override extern(C++) void visit(unknown."~T~"Type cppType)
            {
                throw new Error(\"Attempting to translate a "~T~" type as a struct.\");
            }";
        }
        mixin(Translate("Invalid"));
        mixin(Translate("Builtin"));
        mixin(Translate("Pointer"));
        mixin(Translate("Reference"));
        mixin(Translate("Typedef"));
        mixin(Translate("Enum"));
        mixin(Translate("Union"));
        mixin(Translate("Function"));
        mixin(Translate("Qualified"));
        mixin(Translate("TemplateArgument"));
        mixin(Translate("Array"));
        mixin(Translate("Vector"));

        override public extern(C++) void visit(unknown.NonTemplateRecordType cppType)
        {
            try {
                result = symbolForType[cast(void*)cppType];
            }
            catch (RangeError e)
            {
                unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();
                if (cppDecl !is null)
                {
                    result = new std.d.ast.Symbol();
                    // This symbol will be filled in when the declaration is traversed
                    symbolForType[cast(void*)cppType] = result;
                    unresolvedSymbols[result] = cppDecl;
                }
            }
        }

        override public extern(C++) void visit(unknown.TemplateRecordType cppType)
        {
            try {
                result = symbolForType[cast(void*)cppType];
            }
            catch (RangeError e)
            {
                unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();
                if (cppDecl !is null)
                {
                    result = new std.d.ast.Symbol();
                    // This symbol will be filled in when the declaration is traversed
                    symbolForType[cast(void*)cppType] = result;
                    unresolvedSymbols[result] = cppDecl;
                }
            }
        }

        override public extern(C++) void visit(unknown.TemplateSpecializationType cppType)
        {
            auto deferred = new DeferredTemplateInstantiation();
            deferredTemplates[deferred.answer] = deferred;
            // This is dangerously close to recursion
            // but it isn't because this is the generic template type, not us
            // (the instantiation)
            deferred.templateName = translateType(cppType.getTemplateDeclaration().getType(), QualifierSet.init).type2.symbol;
            assert(deferred.templateName !is null);
            deferred.arguments.length = cppType.getTemplateArgumentCount();
            uint idx = 0;
            for (auto iter = cppType.getTemplateArgumentBegin(),
                    finish = cppType.getTemplateArgumentEnd();
                    !iter.equals(finish);
                    iter.advance(), ++idx )
            {
                deferred.arguments[idx] = translateType(iter.get(), QualifierSet.init);
            }
            symbolForType[cast(void*)cppType] = deferred.answer;
            result = deferred.answer;
        }

        override public extern(C++) void visit(unknown.DelayedType cppType)
        {
            // TODO fill in!
        }
    }
    auto visitor = new RecordTranslationVisitor();
    cppType.visit(visitor);
    type2.symbol = visitor.result;
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

private std.d.ast.Type translate
    (unknown.QualifiedType cppType, QualifierSet qualifiersAlreadApplied)
{
    QualifierSet innerQualifiers;
    if (cppType.isConst() || qualifiersAlreadApplied.const_)
    {
        innerQualifiers.const_ = true;
    }
    std.d.ast.Type result = translateType(cppType.unqualifiedType(), innerQualifiers).clone;

    // Apply qualifiers that ...?
    if (cppType.isConst() && !qualifiersAlreadApplied.const_)
    {
        result.typeConstructors ~= [tok!"const"];
    }

    return result;
}

private std.d.ast.Type replaceFunction(unknown.FunctionType)
{
    // Needed for translating function types, but not declarations,
    // so I'm putting it off until later
    throw new Error("Translation of function types is not implemented yet.");
}

// Qualifiers are the qualifiers that have already been applied to the type.
// e.g. when const(int*) does the const * part then calls translateType(int, const)
// So that const is not applied transitively all the way down
public std.d.ast.Type translateType(unknown.Type cppType, QualifierSet qualifiers)
{
    if (cast(void*)cppType in translated_types)
    {
        return translated_types[cast(void*)cppType];
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
                // TODO maybe this whole function should change?
                // In principle, the Struct strategy should only be used on record types
                result = translateStruct(cppType, qualifiers);
                break;
            case unknown.Strategy.INTERFACE:
                // TODO I should check what the code paths into here are,
                // because you shouldn't translate to interfaces directly,
                // you should translate a pointer or ref to an interface into
                // an interface
                // See Struct case
                result = translateInterface(cppType, qualifiers);
                break;
            case unknown.Strategy.CLASS:
                break;
            case unknown.Strategy.OPAQUE_CLASS:
                break;
        }

        if (result !is null)
        {
            translated_types[cast(void*)cppType] = result;
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
    if (auto s_ptr = (cast(void*)cppDecl.getType()) in symbolForType)
    {
        symbol = *s_ptr;
        // Since the symbol is already in the table, this means
        // that it was used unresolved in a type somewhere.
        // We're resolving it right here, right now.
        unresolvedSymbols.remove(symbol);
    }
    else
    {
        symbol = new std.d.ast.Symbol();
        symbolForType[cast(void*)cppDecl.getType()] = symbol;
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

// We need this because we cannot compute the beginning of template
// instatiations before placing things into modules
// Example: std.container.RedBlackTree!Node
// If we don't know that RedBlackTree is in std.container yet, then we cannot
// produce a symbol that has (std, container, RedBlackTree!Node), since (std, container)
// is not a symbol; we don't have a good way to resolve parts of symbols later.
// This provides that resolution facility.
class DeferredTemplateInstantiation
{
    public:
    std.d.ast.Symbol templateName;
    // TODO non-type arguments
    // Check out std.d.ast.TemplateArgument
    std.d.ast.Type[] arguments;

    std.d.ast.Symbol answer;

    this()
    {
        answer = new std.d.ast.Symbol();
    }

    void resolve()
    {
        auto chain = new std.d.ast.IdentifierOrTemplateChain();
        answer.identifierOrTemplateChain = chain;

        assert(templateName.identifierOrTemplateChain.identifiersOrTemplateInstances.length > 0);
        chain.identifiersOrTemplateInstances = templateName.identifierOrTemplateChain.identifiersOrTemplateInstances[0 .. $-1];
        auto lastIorT = templateName.identifierOrTemplateChain.identifiersOrTemplateInstances[$-1];

        auto iorT = new std.d.ast.IdentifierOrTemplateInstance();
        chain.identifiersOrTemplateInstances ~= [iorT];
        std.d.ast.TemplateInstance templateInstance = new TemplateInstance();
        iorT.templateInstance = templateInstance;

        Token name = lastIorT.identifier;
        templateInstance.identifier = name;
        templateInstance.templateArguments = new std.d.ast.TemplateArguments();
        templateInstance.templateArguments.templateArgumentList = new std.d.ast.TemplateArgumentList();
        auto temp_arg_list = templateInstance.templateArguments.templateArgumentList;
        temp_arg_list.items.length = arguments.length;

        foreach (idx, sym; arguments)
        {
            auto arg = new std.d.ast.TemplateArgument();
            arg.type = sym;
            temp_arg_list.items[idx] = arg;
        }
    }
}
