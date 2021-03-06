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

module translate.types;

import std.conv : to;
import std.range : retro;
import std.stdio : stderr;
import std.typecons : Flag, Yes;
import std.experimental.logger;

import dparse.ast;

static import binder;
static import unknown;

import log_controls;
import translate.decls;
import translate.expr;

static import dast;
import dlang_decls : concat, makeIdentifierOrTemplateChain, makeInstance;

private dast.Type[void*] translated_types;
private dast.Type[string] types_by_name;

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
            // FIXME make sure this cast should succeed
            // (it always will succeed, because this isn't dynamic_cast
            auto decl = cast(unknown.RecordTemplateDeclaration)cppType.getDeclaration();
            //stderr.writeln("Declaration of template record type is:");
            //decl.dump();
            determineRecordTemplateStrategy(decl);
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
            // generic_type is the type represeting the most general template
            // type itself.  We're assuming that all of the specialization will
            // be translated to struct or class together.
            unknown.Type generic_type = parent_template.getTargetType();
            if (generic_type is null)
            {
                assert(0);
            }
            trace("determining strategy of parent_template.");
            determineTemplateStrategy(parent_template);
            //determineStrategy(generic_type);
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

private dast.Type replaceType(unknown.Type cppType, QualifierSet qualifiers)
{
    string replacement_name = binder.toDString(cppType.getReplacement());
    if (replacement_name.length > 0)
    {
        if (auto type_ptr = replacement_name in types_by_name)
        {
            return *type_ptr;
        }
        else
        {
            auto result = new dast.ReplacedType();
            types_by_name[replacement_name] = result;
            result.fullyQualifiedName = makeIdentifierOrTemplateChain!"."(replacement_name);
            assert(result.fullyQualifiedName !is null);

            return result;
        }
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
                public dast.Type result;
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
                    //result = resolveTemplateSpecializationTypeSymbol(cppType);
                    //determineStrategy(cppType);
                    result = startDeclTypeBuild(cppType.getTemplateDeclaration());
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
                        /+ TODO reexamine the delayed types in light of new AST.
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
                        dast.Type qualifier = resolveOrDefer(qualifierType);
                        auto deferred = new DeferredSymbolConcatenation(qualifier);

                        foreach (string name; identifier_stack.retro)
                        {
                            dparse.ast.IdentifierOrTemplateInstance instance = makeInstance(name);
                            deferred.append(instance);
                        }
                        result = new dparse.ast.Type();
                        result.type2 = new dparse.ast.Type2();
                        result.type2.symbol = deferred.answer;

                        qualifier.addDependency(deferred);+/
                        assert(0);
                    }
                }
            }

            auto visitor = new TranslateTypeClass();
            cppType.visit(visitor);
            translated_types[cast(void*)cppType] = visitor.result;
            return visitor.result;
        }
    }
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

private dast.Type translatePointerOrReference
    (Flag!"ref" ref_)
    (unknown.PointerOrReferenceType cppType, QualifierSet qualifiers)
{
    unknown.Type target_type = cppType.getPointeeType();
    // If a strategy is already picked, then this returns immediately
    determineStrategy(target_type);

    dast.Type result;
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
            dast.Type translatedTargetType = translateType(target_type, qualifiers);
            // Function pointers don't need the '*'
            if (target_type.getKind() == unknown.Type.Kind.Function)
            {
                result = translatedTargetType;
                return result;
            }

            result = new dast.PointerType(translatedTargetType);

            /+ TODO something with these type constructors!
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
            }+/
        }
    }

    return result;
}

// TODO Fold these into the strategy visitor
private dast.Type translatePointer(unknown.PointerOrReferenceType cppType, QualifierSet qualifiers)
{
    return translatePointerOrReference!(Flag!"ref".no)(cppType, qualifiers);
}
private dast.Type translateReference(unknown.ReferenceType cppType, QualifierSet qualifiers)
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
private dast.Type resolveOrDefer(Type)(Type cppType)
{
    if (auto type_ptr = (cast(void*)cppType) in translated_types)
    {
        return (*type_ptr);
    }
    else
    {
        unknown.Declaration cppDecl = cppType.getDeclaration();
        dast.Type result;
        if (cppDecl !is null)
        {
            if (!cppDecl.isWrappable())
            {
                throw new UnwrappableTypeDeclaration(cppType, cppDecl);
            }
            // cppDecl.getType() can be different than cppType
            // FIXME I need to find a better way to fix this at the source
            if (auto type_ptr = cast(void*)cppDecl.getType() in translated_types)
            {
                return *type_ptr;
            }
            // Don't allow refs here becuase those should go though a different
            // path, namely the translateReference path.
            if (!cppType.isWrappable(false))
            {
                throw new Exception("This type is not wrappable.");
            }

            result = startDeclTypeBuild(cppDecl);
            // result can be a ReplacedType, not a decl
            translated_types[cast(void*)cppDecl.getType()] = result;
        }
        if (result is null)
        {
            stderr.writeln("Could not build a D AST Type node for");
            cppType.dump();
            assert(result !is null);
        }
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        return result;
    }
}

class TemplateArgumentVisitor : unknown.DeclarationVisitor
{
    extern(C++) override void visitFunction(unknown.FunctionDeclaration) { }
    extern(C++) override void visitNamespace(unknown.NamespaceDeclaration) { }
    extern(C++) override void visitRecord(unknown.RecordDeclaration) { } // FIXME Need to check for template?
    extern(C++) override void visitTypedef(unknown.TypedefDeclaration) { }
    extern(C++) override void visitEnum(unknown.EnumDeclaration) { }
    extern(C++) override void visitEnumConstant(unknown.EnumConstantDeclaration) { }
    extern(C++) override void visitField(unknown.FieldDeclaration) { }
    extern(C++) override void visitUnion(unknown.UnionDeclaration) { } // FIXME Need to check for template?
    extern(C++) override void visitSpecializedRecord(unknown.SpecializedRecordDeclaration) { }
    extern(C++) override void visitMethod(unknown.MethodDeclaration) { }
    extern(C++) override void visitConstructor(unknown.ConstructorDeclaration) { }
    extern(C++) override void visitDestructor(unknown.DestructorDeclaration) { }
    extern(C++) override void visitArgument(unknown.ArgumentDeclaration) { }
    extern(C++) override void visitVariable(unknown.VariableDeclaration) { }
    extern(C++) override void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration) { }
    extern(C++) override void visitTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration) { }
    extern(C++) override void visitUnwrappable(unknown.UnwrappableDeclaration) { }

    unknown.TemplateArgumentIterator first;
    unknown.TemplateArgumentIterator finish;

    void getIterators(Declaration)(Declaration cppDecl)
    {
        first = cppDecl.getTemplateArgumentBegin();
        finish = cppDecl.getTemplateArgumentEnd();
    }

    extern(C++) override void visitRecordTemplate(unknown.RecordTemplateDeclaration cppDecl) { getIterators(cppDecl); }
    extern(C++) override void visitUsingAliasTemplate(unknown.UsingAliasTemplateDeclaration cppDecl) { getIterators(cppDecl); }
}

// FIXME duplication with TranslatorVisitor.translateTemplateArguments
package dast.Type resolveTemplateSpecializationTypeSymbol
    (TargetType)
    (unknown.TemplateSpecializationType cppType)
{
    // Since I can't translate variadic templates, make sure that this is not
    // the fixed-argument-length specialization of a variadic template.
    // TODO implment variadic templates
    unknown.Declaration parent = cppType.getTemplateDeclaration();
    // I can't use inheritance of an interface to stash the template methods,
    // so we're using a visitor for now.
    auto visitor = new TemplateArgumentVisitor();
    parent.visit(visitor);
    for (auto iter = visitor.first,
            finish = visitor.finish;
            !iter.equals(finish);
            iter.advance())
    {
        if (iter.isPack())
        {
            throw new Exception("Cannot translate variadic templates");
        }
    }

    auto result = new TargetType();
    // FIXME abusing the startDeclTypeBuild call
    result.genericParent = cast(typeof(result.genericParent))startDeclTypeBuild(parent);

    auto args = dast.TemplateArgumentInstanceList([]);
    // FIXME use an appender or something instead of ~=
    for (auto iter = cppType.getTemplateArgumentBegin(),
            finish = cppType.getTemplateArgumentEnd();
            !iter.equals(finish);
            iter.advance())
    {
        final switch (iter.getKind())
        {
            case unknown.TemplateArgumentInstanceIterator.Kind.Type:
                auto argType = translateType(iter.getType(), QualifierSet.init);
                args.arguments ~= [new dast.TemplateTypeArgumentInstance(argType)];
                break;
            case unknown.TemplateArgumentInstanceIterator.Kind.Integer:
                dast.Expression e = new dast.IntegerLiteralExpression(iter.getInteger());
                args.arguments ~= [new dast.TemplateValueArgumentInstance(e)];
                break;
            case unknown.TemplateArgumentInstanceIterator.Kind.Expression:
                dast.Expression e = translateExpression(iter.getExpression());
                args.arguments ~= [new dast.TemplateValueArgumentInstance(e)];
                break;
            case unknown.TemplateArgumentInstanceIterator.Kind.Pack:
                throw new Exception("Cannot resolve template argument that is a Pack (...)");
        }
    }
    result.arguments = args;
    return result;
}

// TODO merge this in to the mixin
// TODO figure out if this is a specific instantation or not
private dast.Type resolveOrDeferTemplateArgumentTypeSymbol(unknown.TemplateArgumentType cppType)
{
    if (auto type_ptr = cast(void*)cppType in translated_types)
    {
        return (*type_ptr);
    }
    else
    {
        unknown.TemplateTypeArgumentDeclaration cppDecl = cppType.getTemplateTypeArgumentDeclaration();
        if (cppDecl !is null)
        {
            auto result = new dast.TemplateArgumentType();
            result.name = binder.toDString(cppDecl.getTargetName());
            // This symbol will be filled in when the declaration is traversed
            translated_types[cast(void*)cppType] = result;
            return result;
        }
        assert(0);
        // cppDecl can be null if the type is a builtin type,
        // i.e., when it is not declared in the C++ anywhere
        // TODO figure out if this is reachable
    }
}

// TODO maybe this goes away?
// FIXME qualifiers is ignored
private dast.Type resolveOrDeferType(Type)(Type cppType, QualifierSet qualifiers)
{
    dast.Type result = resolveOrDefer(cppType);
    return result;
}

// Need this to determine whether to do templates or not
// There might be a better way to do this.
// This was translateInterface(string kind)(args), but that caused
// and ICE in dmd 2.066.1.  It does not ICE in dmd master
// (37e6395849fd762bcc1ec1ac036fff79db2d2693)
// FIXME collapse into template
private dast.Type translateInterface(unknown.Type cppType, QualifierSet qualifiers)
{
    class RecordTranslationVisitor : unknown.TypeVisitor
    {
        public dast.Type result;

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
            result = resolveTemplateSpecializationTypeSymbol!(dast.SpecializedInterfaceType)(cppType);
        }

        override public extern(C++) void visit(unknown.DelayedType cppType)
        {
            // TODO fill in!
            assert(0);
        }
    }
    auto visitor = new RecordTranslationVisitor();
    cppType.visit(visitor);
    return visitor.result;
}
private dast.Type translateStruct(unknown.Type cppType, QualifierSet qualifiers)
{
    class RecordTranslationVisitor : unknown.TypeVisitor
    {
        public dast.Type result;

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
            result = resolveTemplateSpecializationTypeSymbol!(dast.SpecializedStructType)(cppType);
        }

        override public extern(C++) void visit(unknown.DelayedType cppType)
        {
            unknown.Type resolved = cppType.resolveType();
            resolved.visit(this);
        }
    }
    auto visitor = new RecordTranslationVisitor();
    cppType.visit(visitor);
    return visitor.result;
}

// I tried to call this dup, but then I couldn't use dup on the inside
dparse.ast.Type clone(dparse.ast.Type t)
{
    auto result = new dparse.ast.Type();
    if (t.typeConstructors !is null) result.typeConstructors = t.typeConstructors.dup;
    if (t.typeSuffixes !is null) result.typeSuffixes = t.typeSuffixes.dup;
    result.type2 = t.type2;
    return result;
}

// TODO do I still need this function?
// FIXME this name isn't great
private dast.Type resolveOrDeferType
    (unknown.QualifiedType cppType, QualifierSet qualifiersAlreadyApplied)
{
    QualifierSet innerQualifiers;
    if (cppType.isConst() || qualifiersAlreadyApplied.const_)
    {
        innerQualifiers.const_ = true;
    }
    dast.Type result = translateType(cppType.unqualifiedType(), innerQualifiers);

    // Apply qualifiers that ...?
    if (cppType.isConst() && !qualifiersAlreadyApplied.const_)
    {
        result = new dast.ConstType(result);
    }

    return result;
}

private dast.FunctionType replaceFunction(unknown.FunctionType cppType)
{
    auto result = new dast.FunctionType();
    // Needed for translating function types, but not declarations,
    result.returnType = translateType(cppType.getReturnType(), QualifierSet.init);

    // TODO handle varargs case
    result.varargs = false;
    foreach (unknown.Type arg_type; cppType.getArgumentRange())
    {
        auto param = new dast.Argument();
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
            param.type = translateType(targetType, QualifierSet.init);
            param.ref_ = Yes.ref_;
        }
        result.arguments ~= [param];
    }
    return result;
}

private dast.Type replaceArray(unknown.ArrayType cppType, QualifierSet qualifiers)
{
    dast.Type result;
    unknown.Type element_type = cppType.getElementType();
    // If a strategy is already picked, then this returns immediately
    determineStrategy(element_type);

    if (element_type.isReferenceType())
    {
        throw new Exception("ERROR: Do not know how to translate a variable length array of reference types.");
    }

    dast.Type elementType = translateType(element_type, qualifiers);
    if (cppType.isFixedLength())
    {
        auto arrayResult = new dast.ArrayType();
        arrayResult.elementType = elementType;

        if (cppType.isDependentLength())
        {
            arrayResult.length = translateExpression(cppType.getLengthExpression());
        }
        else
        {
            arrayResult.length = new dast.IntegerLiteralExpression(cppType.getLength());
        }

        result = arrayResult;
    }
    else
    {
        result = new dast.PointerType(elementType);
    }

    // TODO deal with type constructors again!
    /+if (translatedElementType.typeConstructors.length > 0)
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
    }+/

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
            // TODO find a way to log that there is no decl
            unknown.Declaration decl = type.getDeclaration();
            if (decl !is null)
            {
                string name = binder.toDString(decl.getSourceName());
                if (name.length == 0)
                {
                    stderr.writeln("^ unwrappable type.");
                }
                msg = "Type (" ~ name ~") is not wrappable.";
            }
        }
    }
}

// Qualifiers are the qualifiers that have already been applied to the type.
// e.g. when const(int*) does the const * part then calls translateType(int, const)
// So that const is not applied transitively all the way down
public dast.Type translateType(unknown.Type cppType, QualifierSet qualifiers)
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
        dast.Type result;
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

/+package DeferredSymbolConcatenation makeSymbolForTypeDecl
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
    auto inst = new dparse.ast.IdentifierOrTemplateInstance();
    inst.identifier = targetName;
    return makeSymbolForTypeDecl(cppDecl, inst, package_name, internal_path, namespace_path);
}
package DeferredSymbolConcatenation makeSymbolForTypeDecl
    (SourceDeclaration)
    (SourceDeclaration cppDecl, TemplateInstance targetName, IdentifierChain package_name, DeferredSymbol internal_path, string namespace_path)
{
    auto inst = new dparse.ast.IdentifierOrTemplateInstance();
    inst.templateInstance = targetName;
    return makeSymbolForTypeDecl(cppDecl, inst, package_name, internal_path, namespace_path);
}

// These won't be neccesary when I have a proper AST
interface Resolvable
{
    public void resolve();

    public dparse.ast.IdentifierOrTemplateInstance[] getChain();
}
class DeferredSymbol : Resolvable
{
    public:
    dparse.ast.Symbol answer;

    this() pure
    {
        answer = new dparse.ast.Symbol();
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
    // Check out dparse.ast.TemplateArgument
    dparse.ast.TemplateArgument[] arguments;

    this() pure
    {
        super();
        resolved = false;
    }

    override void resolve()
    {
        if (resolved) return;
        auto chain = new dparse.ast.IdentifierOrTemplateChain();
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

        auto iorT = new dparse.ast.IdentifierOrTemplateInstance();
        chain.identifiersOrTemplateInstances ~= [iorT];
        dparse.ast.TemplateInstance templateInstance = new TemplateInstance();
        iorT.templateInstance = templateInstance;

        Token name = lastIorT.identifier;
        templateInstance.identifier = name;
        templateInstance.templateArguments = new dparse.ast.TemplateArguments();
        templateInstance.templateArguments.templateArgumentList = new dparse.ast.TemplateArgumentList();
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
        auto chain = new dparse.ast.IdentifierOrTemplateChain();
        answer.identifierOrTemplateChain = chain;

        if (components.length == 0)
        {
            warning(logEmptyDeferredSymbols, "Never filled in symbol concatenation ", cast(void*)this);
        }
        // TODO make sure all the components are resolved
        foreach (DeferredSymbol dependency; components)
        {
            dependency.resolve();
            dparse.ast.Symbol symbol = dependency.answer;
            dparse.ast.IdentifierOrTemplateChain sub_chain = symbol.identifierOrTemplateChain;
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
+/

// FIXME needs a better name
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
