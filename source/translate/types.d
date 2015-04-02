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

import std.conv : to;
import std.range : retro;
import std.stdio : stderr;
import std.typecons : Flag;
import std.experimental.logger;

import std.d.ast;
import std.d.lexer;

static import binder;
static import unknown;

import log_controls;
import translate.expr;
import translate.decls : exprForDecl;

import dlang_decls : concat, makeIdentifierOrTemplateChain, makeInstance;

private std.d.ast.Type[void*] translated_types;
private std.d.ast.Type[string] types_by_name;
package DeferredSymbolConcatenation[void*] symbolForType;
package unknown.Declaration[DeferredSymbol] unresolvedSymbols;
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
            if (dumpBeforeThrowing) cppType.dump();
            throw new Exception("Attempting to determine strategy for invalid type (cppType=" ~ to!string(cast(void*)cppType)~ ").");
        }

        override extern(C++) void visit(unknown.BuiltinType cppType)
        {
            stderr.write("I don't know how to translate the builtin C++ type:\n");
            cppType.dump();
            stderr.write("\n");
            throw new Exception("Cannot translate builtin.");
        }

        mixin template Replace(T) {
            override extern(C++) void visit(T cppType)
            {
                // FIXME empty string means resolve to an actual AST type, not a string
                cppType.chooseReplaceStrategy(binder.toBinderString(""));
            }
        }
        mixin Replace!(unknown.PointerType);
        mixin Replace!(unknown.ReferenceType);
        override extern(C++) void visit(unknown.TypedefType cppType)
        {
            determineStrategy(cppType.getTargetType());
            // FIXME verify and comment on why replace is always the right
            // strategy, even if the target is an interface
            cppType.chooseReplaceStrategy(binder.toBinderString(""));
        }
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

        mixin Replace!(unknown.ArrayType);

        override extern(C++) void visit(unknown.VectorType cppType)
        {
            throw new Exception("Cannot translate vector (e.g. SSE, AVX) types.");
        }

        override extern(C++) void visit(unknown.QualifiedType cppType)
        {
            determineStrategy(cppType.unqualifiedType());
            cppType.chooseReplaceStrategy(binder.toBinderString(""));
        }

        override extern(C++) void visit(unknown.TemplateSpecializationType cppType)
        {
            // The template could be unwrappable, but we wouldn't know that
            // until we try to resolve the generic template.  I think.
            unknown.Declaration parent_template = cppType.getTemplateDeclaration();
            if (!parent_template.isWrappable())
            {
                throw new Exception("The template for this specialization is not wrappable.");
            }
            unknown.Type generic_type = parent_template.getType();
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
            unknown.Type backing = cppType.resolveType();
            if (backing !is null)
            {
                determineStrategy(backing);
                if (backing.getStrategy() == unknown.Strategy.REPLACE)
                {
                    cppType.chooseReplaceStrategy(binder.toBinderString(""));
                }
                else
                {
                    cppType.setStrategy(backing.getStrategy());
                }
            }
            else
            {
                // WE'RE DOING IT LIVE
                // TODO emit a warning
                cppType.chooseReplaceStrategy(binder.toBinderString(""));
            }
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
        if (auto type_ptr = replacement_name in types_by_name)
        {
            return *type_ptr;
        }
        else
        {
            result = new std.d.ast.Type();
            types_by_name[replacement_name] = result;
            result.type2 = new Type2();
            result.type2.symbol = new std.d.ast.Symbol();
            result.type2.symbol.identifierOrTemplateChain = makeIdentifierOrTemplateChain!"."(replacement_name);
            assert(result.type2.symbol.identifierOrTemplateChain !is null);
        }

        return result;
    }
    else
    {
        if (auto type_ptr = cast(void*)cppType in translated_types)
        {
            return translated_types[cast(void*)cppType];
        }
        else
        {
            // TODO this is capturing "qualifiers" from the function scope
            // Make sure that works with recursion
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
                        result = resolveOrDeferType(cppType, qualifiers);
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
                    result = replaceArray(cppType, qualifiers);
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
                    DeferredSymbol deferred = resolveTemplateSpecializationTypeSymbol(cppType);
                    result = new std.d.ast.Type();
                    result.type2 = new std.d.ast.Type2();
                    result.type2.symbol = deferred.answer;
                }

                extern(C++) void visit(unknown.DelayedType type)
                {
                    unknown.Type backing_type = type.resolveType();
                    if (backing_type !is null)
                    {
                        result = replaceType(backing_type, qualifiers);
                    }
                    else
                    {
                        // DECIDED TO DO IT LIVE
                        string[] identifier_stack = [binder.toDString(type.getIdentifier())];
                        unknown.NestedNameWrapper current_name;
                        for (current_name = type.getQualifier(); current_name.isIdentifier(); current_name = current_name.getPrefix())
                        {
                            identifier_stack ~= [binder.toDString(current_name.getAsIdentifier())];
                        }
                        assert(current_name.isType());

                        unknown.Type qualifierType = current_name.getAsType();
                        if (qualifierType.getKind() == unknown.Type.Kind.Invalid)
                        {
                            throw new Exception("Type is dependent on an invalid type.");
                        }
                        DeferredSymbol qualifier = resolveOrDefer(qualifierType);
                        auto deferred = new DeferredSymbolConcatenation(qualifier);

                        foreach (string name; identifier_stack.retro)
                        {
                            std.d.ast.IdentifierOrTemplateInstance instance = makeInstance(name);
                            deferred.append(instance);
                        }
                        result = new std.d.ast.Type();
                        result.type2 = new std.d.ast.Type2();
                        result.type2.symbol = deferred.answer;

                        qualifier.addDependency(deferred);
                    }
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
    unknown.Declaration declaration;
    this(unknown.Type t, unknown.Declaration d = null)
    {
        super("Trying to translate into a ref");
        type = t;
        declaration = d;
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

class UnwrappableTypeDeclaration : Exception
{
    this(unknown.Type cppType, unknown.Declaration cppDecl)
    {
        // This does not support unwrappable declarations
        //super("The declaration ("~to!string(cast(void*)cppDecl) ~") for this type ("~to!string(cast(void*)cppType) ~"~" ~to!string(cast(void*)cppDecl.getType()) ~") is not wrappable.");
        super("The declaration ("~to!string(cast(void*)cppDecl) ~") for this type ("~to!string(cast(void*)cppType) ~") is not wrappable.");
    }
}

// TODO Before I made this into a mixin, these checked the kinds of the types
// passed in to make sure that the correct function was being called.  I.e.
// check that cppType was a union, enum, etc.
private DeferredSymbol resolveOrDefer(Type)(Type cppType)
{
    if (auto deferred_ptr = cast(void*)cppType in symbolForType)
    {
        return (*deferred_ptr);
    }
    else
    {
        unknown.Declaration cppDecl = cppType.getDeclaration();
        DeferredSymbolConcatenation result = null;
        if (cppDecl !is null)
        {
            if (!cppDecl.isWrappable())
            {
                if (dumpBeforeThrowing) cppDecl.dump();
                throw new UnwrappableTypeDeclaration(cppType, cppDecl);
            }
            // cppDecl.getType() can be different than cppType
            // FIXME I need to find a better way to fix this at the source
            if (auto deferred_ptr = cast(void*)cppDecl.getType() in symbolForType)
            {
                return *deferred_ptr;
            }
            // Don't allow refs here becuase those should go though a different
            // path, namely the translateReference path.
            if (!cppType.isWrappable(false))
            {
                if (dumpBeforeThrowing) cppDecl.dump();
                throw new Exception("This type is not wrappable.");
            }
            result = new DeferredSymbolConcatenation();
            // This symbol will be filled in when the declaration is traversed
            symbolForType[cast(void*)cppDecl.getType()] = result;
            unresolvedSymbols[result] = cppDecl;
        }
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        return result;
    }
}

private DeferredSymbol resolveOrDefer(unknown.TemplateArgumentType cppType)
{
    if (auto deferred_ptr = cast(void*)cppType in symbolForType)
    {
        return (*deferred_ptr);
    }
    else
    {
        string name = binder.toDString(cppType.getIdentifier());
        auto result = new DeferredSymbolConcatenation(makeInstance(name));
        symbolForType[cast(void*)cppType] = result;
        return result;
    }
}

// FIXME duplication with TranslatorVisitor.translateTemplateArguments
package DeferredSymbol resolveTemplateSpecializationTypeSymbol(unknown.TemplateSpecializationType cppType)
{
    // Since I can't translate variadic templates, make sure that this is not
    // the fixed-argument-length specialization of a variadic template.
    // TODO implment variadic templates
    unknown.Declaration parent = cppType.getTemplateDeclaration();
    // FIXME this is a super-bad assumption
    auto record_parent = cast(unknown.RecordTemplateDeclaration) parent;
    for (auto iter = record_parent.getTemplateArgumentBegin(),
            finish = record_parent.getTemplateArgumentEnd();
            !iter.equals(finish);
            iter.advance())
    {
        if (iter.isPack())
        {
            throw new Exception("Cannot translate variadic templates");
        }
    }

    // This is dangerously close to recursion
    // but it isn't because this is the generic template type, not us
    // (the instantiation)
    // TODO template_symbol needs a better name
    auto template_symbol = new DeferredTemplateInstantiation();
    template_symbol.templateName = resolveOrDefer(cppType.getTemplateDeclaration().getType());
    assert(template_symbol.templateName !is null);
    template_symbol.arguments.length = cppType.getTemplateArgumentCount();
    uint idx = 0;
    for (auto iter = cppType.getTemplateArgumentBegin(),
            finish = cppType.getTemplateArgumentEnd();
            !iter.equals(finish);
            iter.advance(), ++idx )
    {
        template_symbol.arguments[idx] = new std.d.ast.TemplateArgument();
        std.d.ast.TemplateArgument current = template_symbol.arguments[idx];
        final switch (iter.getKind())
        {
            case unknown.TemplateArgumentInstanceIterator.Kind.Type:
                current.type = translateType(iter.getType(), QualifierSet.init);
                break;
            case unknown.TemplateArgumentInstanceIterator.Kind.Integer:
                current.assignExpression = new std.d.ast.AssignExpression();
                auto constant = new std.d.ast.PrimaryExpression();
                constant.primary = Token(tok!"longLiteral", to!string(iter.getInteger()), 0, 0, 0);
                current.assignExpression = constant;
                break;
            case unknown.TemplateArgumentInstanceIterator.Kind.Expression:
                current.assignExpression = new std.d.ast.AssignExpression();
                current.assignExpression = translateExpression(iter.getExpression());
                break;
            case unknown.TemplateArgumentInstanceIterator.Kind.Pack:
                throw new Exception("Cannot resolve template argument that is a Pack (...)");
        }
    }
    auto deferred = new DeferredSymbolConcatenation(template_symbol);
    symbolForType[cast(void*)cppType] = deferred;
    unresolvedSymbols[deferred] = null;
    return deferred;
}

// TODO merge this in to the mixin
private DeferredSymbol resolveOrDeferTemplateArgumentTypeSymbol(unknown.TemplateArgumentType cppType)
{
    if (auto deferred_ptr = cast(void*)cppType in symbolForType)
    {
        return (*deferred_ptr);
    }
    else
    {
        unknown.TemplateTypeArgumentDeclaration cppDecl = cppType.getTemplateTypeArgumentDeclaration();
        DeferredSymbolConcatenation result = null;
        if (cppDecl !is null)
        {
            result = new DeferredSymbolConcatenation();
            string name = binder.toDString(cppDecl.getTargetName());
            result.append(makeIdentifierOrTemplateChain!"."(name));
            // This symbol will be filled in when the declaration is traversed
            symbolForType[cast(void*)cppType] = result;
            // Template arguments are always in the local scope, so they are
            // always resolved.  Don't put them into the unresolved set.
            unresolvedSymbols[result] = cppDecl;
        }
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        return result;
    }
}

private std.d.ast.Type resolveOrDeferType(Type)(Type cppType, QualifierSet qualifiers)
{
    auto result = new std.d.ast.Type();
    auto type2 = new std.d.ast.Type2();
    result.type2 = type2;
    enum kind = Type.stringof;
    DeferredSymbol deferred = resolveOrDefer(cppType);
    if (deferred !is null)
    {
        type2.symbol = deferred.answer;
    }
    else
    {
        throw new Exception("Could not resolve or defer type.");
    }
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
        public DeferredSymbol result;

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
            result = resolveOrDefer(cppType);
        }

        // This needs to come up with a symbol that describes the template generally,
        // e.g. std::unordered_map, without template args
        override public extern(C++) void visit(unknown.TemplateRecordType cppType)
        {
            result = resolveOrDefer(cppType);
        }

        override public extern(C++) void visit(unknown.TemplateSpecializationType cppType)
        {
            result = resolveTemplateSpecializationTypeSymbol(cppType);
        }

        override public extern(C++) void visit(unknown.DelayedType cppType)
        {
            // TODO fill in!
        }
    }
    auto visitor = new RecordTranslationVisitor();
    cppType.visit(visitor);
    type2.symbol = visitor.result.answer;
    return result;
}
private std.d.ast.Type translateStruct(unknown.Type cppType, QualifierSet qualifiers)
{
    auto result = new std.d.ast.Type();
    auto type2 = new std.d.ast.Type2();
    result.type2 = type2;

    class RecordTranslationVisitor : unknown.TypeVisitor
    {
        public DeferredSymbol result;

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
            result = resolveOrDefer(cppType);
        }

        override public extern(C++) void visit(unknown.TemplateRecordType cppType)
        {
            result = resolveOrDefer(cppType);
        }

        override public extern(C++) void visit(unknown.TemplateSpecializationType cppType)
        {
            result = resolveTemplateSpecializationTypeSymbol(cppType);
        }

        override public extern(C++) void visit(unknown.DelayedType cppType)
        {
            unknown.Type resolved = cppType.resolveType();
            result = resolveOrDefer(resolved);
        }
    }
    auto visitor = new RecordTranslationVisitor();
    cppType.visit(visitor);
    type2.symbol = visitor.result.answer;
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

// FIXME this name isn't great
private std.d.ast.Type resolveOrDeferType
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
        auto outer = new std.d.ast.Type();
        outer.type2 = new std.d.ast.Type2();
        outer.type2.typeConstructor = tok!"const";
        outer.type2.type = result;
        result = outer;
    }

    return result;
}

private std.d.ast.Type replaceFunction(unknown.FunctionType cppType)
{
    // Needed for translating function types, but not declarations,
    std.d.ast.Type returnType = translateType(cppType.getReturnType(), QualifierSet.init).clone;
    auto suffix = new std.d.ast.TypeSuffix();
    suffix.delegateOrFunction = Token(tok!"function", "", 0, 0, 0);
    returnType.typeSuffixes ~= [suffix];

    auto parameters = new std.d.ast.Parameters();
    // TODO handle varargs case
    parameters.hasVarargs = false;
    foreach (unknown.Type arg_type; cppType.getArgumentRange())
    {
        auto param = new std.d.ast.Parameter();
        try {
            param.type = translateType(arg_type, QualifierSet.init);
        }
        catch (RefTypeException e)
        {
            // Make sure that this isn't a ref farther down, since the ref
            // modifier can only be applied to the parameter
            if (e.type != cppType)
            {
                throw e;
            }

            unknown.Type targetType = (cast(unknown.ReferenceType)cppType).getPointeeType();
            param.type = translateType(targetType, QualifierSet.init).clone;
            param.type.typeConstructors ~= [tok!"ref"];
        }
        parameters.parameters ~= [param];
    }
    return returnType;
}

private std.d.ast.Type replaceArray(unknown.ArrayType cppType, QualifierSet qualifiers)
{
    auto result = new std.d.ast.Type();
    unknown.Type element_type = cppType.getElementType();
    // If a strategy is already picked, then this returns immediately
    determineStrategy(element_type);

    if (element_type.isReferenceType())
    {
        throw new Exception("ERROR: Do not know how to translate a variable length array of reference types.");
    }

    std.d.ast.Type translatedElementType = translateType(element_type, qualifiers).clone;
    if (cppType.isFixedLength())
    {
        TypeSuffix arraySuffix = new TypeSuffix();
        arraySuffix.array = true;
        arraySuffix.low = new std.d.ast.AssignExpression();
        if (cppType.isDependentLength())
        {
            arraySuffix.low = translateExpression(cppType.getLengthExpression());
        }
        else
        {
            // FIXME duplication with translateEnumConstant
            auto constant = new std.d.ast.PrimaryExpression();

            constant.primary = Token(tok!"longLiteral", to!string(cppType.getLength()), 0, 0, 0);
            arraySuffix.low = constant;
        }
        result.typeSuffixes = [arraySuffix];
    }
    else
    {
        // FIXME copy-pasted from replacePointerOrReference
        TypeSuffix pointerSuffix = new TypeSuffix();
        pointerSuffix.star = Token(tok!"*", "", 0, 0, 0);
        result.typeSuffixes = [pointerSuffix];
    }

    if (translatedElementType.typeConstructors.length > 0)
    {
        result.type2 = new Type2();
        result.type2.typeConstructor = translatedElementType.typeConstructors[0];
        translatedElementType.typeConstructors = translatedElementType.typeConstructors[1 .. $];
        result.type2.type = translatedElementType;
    }
    else
    {
        // FIXME potentially does many concatenations; there should be a way
        // to build them all into the same array.
        // But this probably won't be a real problem, because
        // how deep do people's types actually go? (Don't answer that!)
        result.typeSuffixes ~= translatedElementType.typeSuffixes;
        result.type2 = translatedElementType.type2;
    }

    return result;
}

class UnwrappableType : Exception
{
    public:
    unknown.Type type;

    this(unknown.Type cppType)
    {
        super("Type is not wrappable!");
        type = cppType;
        if (type.hasDeclaration())
        {
            unknown.Declaration decl = type.getDeclaration();
            msg = "Type (" ~ binder.toDString(decl.getSourceName()) ~") is not wrappable.";
        }
    }
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
        if (!cppType.isWrappable(true))
        {
            // If it is a typedef, try translating the target of the typedef
            if (cppType.getKind() == unknown.Type.Kind.Typedef)
            {
                unknown.Type targetType = (cast(unknown.TypedefType)cppType).getTargetType();
                return translateType(targetType, qualifiers);
            }
            else
            {
                throw new UnwrappableType(cppType);
            }
        }
        std.d.ast.Type result;
        try {
            final switch (cppType.getStrategy())
            {
                case unknown.Strategy.UNKNOWN:
                    determineStrategy(cppType);

                    // This if is for debugging; we're going to fail an assert
                    // so this re-plays the logic that got us there
                    if (cppType.getStrategy() == unknown.Strategy.UNKNOWN)
                    {
                        determineStrategy(cppType);
                        assert(cppType.getStrategy != unknown.Strategy.UNKNOWN);
                    }
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
        }
        catch (UnwrappableTypeDeclaration e)
        {
            if (cppType.getKind() == unknown.Type.Kind.Typedef)
            {
                unknown.Type targetType = (cast(unknown.TypedefType)cppType).getTargetType();
                result = translateType(targetType, qualifiers);
            }
            else
            {
                throw e;
            }
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

package DeferredSymbolConcatenation makeSymbolForTypeDecl
    (unknown.Declaration cppDecl, IdentifierOrTemplateInstance targetName, IdentifierChain package_name, DeferredSymbol internal_path, string namespace_path)
{
    import std.array : join;
    import std.algorithm : map;

    DeferredSymbolConcatenation symbol;
    if (auto s_ptr = (cast(void*)cppDecl.getType()) in symbolForType)
    {
        symbol = *s_ptr;
    }
    else
    {
        symbol = new DeferredSymbolConcatenation();
        symbolForType[cast(void*)cppDecl.getType()] = symbol;
    }
    unresolvedSymbols[symbol] = cppDecl;

    DeferredExpression expr;
    if (auto e_ptr = (cast(void*)cppDecl) in exprForDecl)
    {
        expr = *e_ptr;
        expr.symbol = symbol;
    }
    else
    {
        expr = new DeferredExpression(symbol);
        exprForDecl[cast(void*)cppDecl] = expr;
    }

    DeferredSymbol[] original_components = symbol.components;

    if (original_components.length == 0)
    {
        symbol.components = [];
        if (internal_path is null && package_name !is null)
            // Internal path is now a fully qualifed deferred symbol, so
            // it obseletes the package name.
            // FIXME the name "internal_path", since it's not internal anymore
        {
            symbol.components ~= [new ActuallyNotDeferredSymbol(package_name)];
        }
        if (internal_path !is null) // internal_path is null at the top level inside a module
        {
            symbol.components ~= [internal_path];
        }
        else
        {
            auto namespace_chain = makeIdentifierOrTemplateChain!"::"(namespace_path);
            if (namespace_chain.identifiersOrTemplateInstances.length > 0)
                // Things like template arguments aren't really in a namespace
            {
                symbol.append(namespace_chain);
            }
        }

        // The name can be null for things like anonymous unions
        if (targetName !is null)
        {
            symbol.append(targetName);
        }
    }

    assert (symbol.components.length > 0);

    return symbol;
}

package DeferredSymbolConcatenation makeSymbolForTypeDecl
    (SourceDeclaration)
    (SourceDeclaration cppDecl, Token targetName, IdentifierChain package_name, DeferredSymbol internal_path, string namespace_path)
{
    auto inst = new std.d.ast.IdentifierOrTemplateInstance();
    inst.identifier = targetName;
    return makeSymbolForTypeDecl(cppDecl, inst, package_name, internal_path, namespace_path);
}
package DeferredSymbolConcatenation makeSymbolForTypeDecl
    (SourceDeclaration)
    (SourceDeclaration cppDecl, TemplateInstance targetName, IdentifierChain package_name, DeferredSymbol internal_path, string namespace_path)
{
    auto inst = new std.d.ast.IdentifierOrTemplateInstance();
    inst.templateInstance = targetName;
    return makeSymbolForTypeDecl(cppDecl, inst, package_name, internal_path, namespace_path);
}

// These won't be neccesary when I have a proper AST
interface Resolvable
{
    public void resolve();

    public std.d.ast.IdentifierOrTemplateInstance[] getChain();
}
class DeferredSymbol : Resolvable
{
    public:
    std.d.ast.Symbol answer;

    this() pure
    {
        answer = new std.d.ast.Symbol();
    }

    abstract void resolve();

    abstract IdentifierOrTemplateInstance[] getChain();
    abstract void addDependency(Resolvable dep);
}

// Bad idea
class ActuallyNotDeferredSymbol : DeferredSymbol
{
    this(IdentifierChain chain)
    {
        super();
        answer.identifierOrTemplateChain = makeIdentifierOrTemplateChain(chain);
    }

    this(IdentifierOrTemplateInstance inst)
    {
        super();
        answer.identifierOrTemplateChain = makeIdentifierOrTemplateChain(inst);
    }
    this(IdentifierOrTemplateChain chain) pure
    in { assert(chain !is null); }
    body {
        super();
        answer.identifierOrTemplateChain = chain;
    }

    override void resolve() { }

    override IdentifierOrTemplateInstance[] getChain()
    {
        return answer.identifierOrTemplateChain.identifiersOrTemplateInstances[];
    }

    override void addDependency(Resolvable dep)
    {
        dep.resolve();
    }
}

// We need this because we cannot compute the beginning of template
// instatiations before placing things into modules
// Example: std.container.RedBlackTree!Node
// If we don't know that RedBlackTree is in std.container yet, then we cannot
// produce a symbol that has (std, container, RedBlackTree!Node), since (std, container)
// is not a symbol; we don't have a good way to resolve parts of symbols later.
// This provides that resolution facility.
class DeferredTemplateInstantiation : DeferredSymbol
{
    bool resolved;
    Resolvable[] dependencies;
    public:
    DeferredSymbol templateName;
    // TODO non-type arguments
    // Check out std.d.ast.TemplateArgument
    std.d.ast.TemplateArgument[] arguments;

    this() pure
    {
        super();
        resolved = false;
    }

    override void resolve()
    {
        if (resolved) return;
        auto chain = new std.d.ast.IdentifierOrTemplateChain();
        answer.identifierOrTemplateChain = chain;

        templateName.resolve();
        if (templateName.answer.identifierOrTemplateChain.identifiersOrTemplateInstances.length == 0)
        {
            warning(logEmptyDeferredSymbols, "Never filled in template name ", cast(void*)templateName);
            warning(logEmptyDeferredSymbols, "For instantiation ", cast(void*)this);
            return;
        }

        chain.identifiersOrTemplateInstances = templateName.answer.identifierOrTemplateChain.identifiersOrTemplateInstances[0 .. $-1];
        auto lastIorT = templateName.answer.identifierOrTemplateChain.identifiersOrTemplateInstances[$-1];

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

        temp_arg_list.items[] = arguments[];
        resolved = true;

        foreach (d; dependencies)
        {
            d.resolve();
        }
        dependencies = [];
    }

    override IdentifierOrTemplateInstance[] getChain()
    in {
        assert(resolved);
    }
    body {
        return answer.identifierOrTemplateChain.identifiersOrTemplateInstances[];
    }

    override void addDependency(Resolvable dep)
    {
        if (resolved)
        {
            dep.resolve();
        }
        else
        {
            dependencies ~= [dep];
        }
    }
}

class DeferredSymbolConcatenation : DeferredSymbol
{
    private DeferredSymbol[] components;
    private bool resolved;

    private Resolvable[] dependencies;

    public:
    this() pure
    {
        super();
        resolved = false;
    }

    this(DeferredSymbol symbol) pure
    in {
        assert(symbol !is null);
    }
    body {
        super();
        components = [symbol];
        resolved = false;
    }

    this(IdentifierOrTemplateInstance inst)
    {
        super();
        components = [new ActuallyNotDeferredSymbol(inst)];
        resolved = false;
    }

    override void resolve()
    {
        if (resolved) return;
        auto chain = new std.d.ast.IdentifierOrTemplateChain();
        answer.identifierOrTemplateChain = chain;

        if (components.length == 0)
        {
            warning(logEmptyDeferredSymbols, "Never filled in symbol concatenation ", cast(void*)this);
        }
        // TODO make sure all the components are resolved
        foreach (DeferredSymbol dependency; components)
        {
            dependency.resolve();
            std.d.ast.Symbol symbol = dependency.answer;
            std.d.ast.IdentifierOrTemplateChain sub_chain = symbol.identifierOrTemplateChain;
            chain.identifiersOrTemplateInstances ~= sub_chain.identifiersOrTemplateInstances;
        }
        resolved = true;

        foreach (d; dependencies)
        {
            d.resolve();
        }
    }

    DeferredSymbolConcatenation append(DeferredSymbol end) pure
        in { assert(end !is null); }
    body {
        components ~= [end];
        return this; // For chaining
    }
    DeferredSymbolConcatenation append(IdentifierOrTemplateInstance end)
    {
        components ~= [new ActuallyNotDeferredSymbol(end)];
        return this; // For chaining
    }
    DeferredSymbolConcatenation append(IdentifierOrTemplateChain end) pure
    {
        components ~= [new ActuallyNotDeferredSymbol(end)];
        return this; // For chaining
    }
    DeferredSymbolConcatenation append(IdentifierChain end)
    {
        components ~= [new ActuallyNotDeferredSymbol(end)];
        return this; // For chaining
    }

    DeferredSymbolConcatenation append(DeferredSymbol[] chain) pure
    in {
        foreach (sym; chain)
        {
            assert(sym !is null);
        }
    }
    body {
        components ~= chain;
        return this;
    }

    @property
    ulong length() const
    {
        return components.length;
    }

    override IdentifierOrTemplateInstance[] getChain()
    in {
        assert(resolved);
    }
    body {
        return answer.identifierOrTemplateChain.identifiersOrTemplateInstances[];
    }

    override void addDependency(Resolvable dep)
    {
        if (resolved)
        {
            dep.resolve();
        }
        else
        {
            dependencies ~= [dep];
        }
    }
}

// FIXME overload ~
DeferredSymbolConcatenation concat(DeferredSymbol first, DeferredSymbol second) pure
in {
    assert(first !is null);
    assert(second !is null);
}
body {
    auto result = new DeferredSymbolConcatenation();
    result.components = [first, second];
    return result;
}

unknown.Type handleReferenceType(unknown.Type startingPoint)
{
    class RefHandler : unknown.TypeVisitor
    {
        unknown.Type result;
        extern(C++) override void visit(unknown.InvalidType) { }
        extern(C++) override void visit(unknown.BuiltinType) { }
        extern(C++) override void visit(unknown.PointerType) { }
        extern(C++) override void visit(unknown.TemplateRecordType) { }
        extern(C++) override void visit(unknown.NonTemplateRecordType) { }
        extern(C++) override void visit(unknown.UnionType) { }
        extern(C++) override void visit(unknown.ArrayType) { }
        extern(C++) override void visit(unknown.FunctionType) { }
        extern(C++) override void visit(unknown.VectorType) { }
        extern(C++) override void visit(unknown.EnumType) { }
        extern(C++) override void visit(unknown.TemplateArgumentType) { }
        extern(C++) override void visit(unknown.TemplateSpecializationType) { }

        extern(C++) override void visit(unknown.ReferenceType type)
        {
            result = type.getPointeeType();
        }

        extern(C++) override void visit(unknown.TypedefType type)
        {
            type.getTargetType().visit(this);
        }

        extern(C++) override void visit(unknown.DelayedType type)
        {
            unknown.Type r = type.resolveType();
            if (r)
            {
                r.visit(this);
            }
        }

        extern(C++) override void visit(unknown.QualifiedType)
        {
            // TODO I could do something here, but I need to move the qualifier
            // inside the ref
        }
    }

    auto visitor = new RefHandler();
    startingPoint.visit(visitor);

    return visitor.result;
}
