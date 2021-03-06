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

module translate.decls;

import std.algorithm : each;
import std.array;
import std.conv : to;
import std.stdio : stdout, stderr;
import std.typecons : Flag, Yes, No;
import std.experimental.logger;

static import binder;
static import dast;
import dlang_decls : makeIdentifierChain, rootPackage;
static import unknown;
import log_controls;
import manual_types;
import translate.types;
import translate.expr;

private dast.Declaration[void*] translated;
private int[dast.Declaration] placedDeclarations;

Result CHECK_FOR_DECL(Result, Input)(Input cppDecl)
{
    auto ptr = cast(void*)cppDecl in translated;
    if (ptr)
    {
        Result r = cast(Result)(*ptr);
        assert(r !is null);
        return r;
        // ^ This cast failing is a huge internal programmer error
        // ^ This cast was cast(Result) and would always fail
    }
    return null;
}

private dast.LinkageAttribute translateLinkage(T)(T cppDecl, string namespace_path)
{
    immutable clang.LanguageLinkage linkage = cppDecl.getLinkLanguage();
    if (linkage == manual_types.LanguageLinkage.CLanguageLinkage)
    {
        return new dast.CLinkageAttribute();
    }
    else if (linkage == clang.LanguageLinkage.CXXLanguageLinkage)
    {
        return new dast.CppLinkageAttribute(namespace_path);
    }
    else if (cppDecl.getLinkLanguage() == clang.LanguageLinkage.NoLanguageLinkage)
    {
        warning(warnIfNoLinkage, "WARNING: \"", namespace_path, "::", binder.toDString(cppDecl.getSourceName()), "\" has no language linkage.  Assuming C++.");
        return new dast.CppLinkageAttribute(namespace_path);
    }
    else {
        throw new Exception("Didn't recognize linkage");
    }
}

private T registerDeclaration(T)(unknown.Declaration cppDecl)
{
    if (cast(void*)cppDecl in translated)
    {
        assert(0);
    }
    T decl = new T();
    translated[cast(void*)cppDecl] = decl;
    return decl;
}

private string nameFromDecl(unknown.Declaration cppDecl)
{
    return binder.toDString(cppDecl.getTargetName());
}

private dast.Visibility translateVisibility(T)(T cppDecl)
{
    final switch (cppDecl.getVisibility())
    {
        case unknown.Visibility.UNSET:
            throw new Exception("Unset visibility");
        case unknown.Visibility.PUBLIC:
            return dast.Visibility.Public;
        case unknown.Visibility.PRIVATE:
            return dast.Visibility.Private;
        case unknown.Visibility.PROTECTED:
            return dast.Visibility.Protected;
        case unknown.Visibility.EXPORT:
            return dast.Visibility.Export;
        case unknown.Visibility.PACKAGE:
            return dast.Visibility.Package;
    }
}

class OverloadedOperatorError : Exception
{
    this()
    {
        super("Cannot translate overloaded operators.");
    }
}

private dast.Module moduleForDeclaration(unknown.Declaration cppDecl)
{
    if (cppDecl.shouldEmit)
    {
        return destination;
    }
    else
    {
        // FIXME
        // return makeIdentifierChain(binder.toDString(cppDecl.getTargetModule()));
        assert(0);
    }
}

enum VirtualBehavior {
    ALLOWED,
    REQUIRED,
    FORBIDDEN,
}
private class TranslatorVisitor : unknown.DeclarationVisitor
{
    string namespace_path;

    public:
    dast.Declaration[] last_result;

    public:
    this()
    {
        namespace_path = "";
        last_result = null;
    }

    this(string nsp)
    {
        namespace_path = nsp;
        last_result = null;
    }

    dast.Declaration[] visit(unknown.Declaration cppDecl)
    {
        try {
            cppDecl.visit(this);
            return last_result;
        }
        catch (RefTypeException e)
        {
            if (!e.declaration)
            {
                e.declaration = cppDecl;
            }
            throw e;
        }
    }

    dast.FunctionDeclaration translateFunction(unknown.FunctionDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.FunctionDeclaration)(cppDecl);
        if (result !is null) return result;

        result = registerDeclaration!(dast.FunctionDeclaration)(cppDecl);
        // Set the linkage attributes for this function
        result.linkage = translateLinkage(cppDecl, namespace_path);

        binder.binder.string target_name = cppDecl.getTargetName();
        if (target_name.size())
        {
            result.name = nameFromDecl(cppDecl);
        }
        else
        {
            throw new Exception("Function declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        try {
            result.setReturnType(translateType(cppDecl.getReturnType(), QualifierSet.init));
        }
        catch (RefTypeException e)
        {
            unknown.Type targetType = handleReferenceType(cppDecl.getReturnType());
            if (targetType)
            {
                result.setReturnType(translateType(targetType, QualifierSet.init), Yes.ref_);
            }
            else
            {
                throw e;
            }
        }

        // FIXME obviously not always true
        result.varargs = false;

        for (auto arg_iter = cppDecl.getArgumentBegin(), arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance())
        {
            result.arguments ~= [translateArgument(arg_iter.get())];
        }
        return result;
    }
    extern(C++) override
    void visitFunction(unknown.FunctionDeclaration cppDecl)
    {
        if (cppDecl.isOverloadedOperator())
        {
            stderr.writeln("ERROR: Cannot translate overloaded operator.");
            last_result = null;
        }
        else
        {
            last_result = [translateFunction(cppDecl)];
        }
    }

    void translateNamespace(unknown.NamespaceDeclaration cppDecl)
    {
        // This needs to be source name because the namespace path dictates the mangling
        string this_namespace_path = namespace_path ~ "::" ~ binder.toDString(cppDecl.getSourceName());
        // visit and translate all of the children
        foreach (child; cppDecl.getChildren())
        {
            LogLevel old_level = sharedLog.logLevel;
            scope(exit) sharedLog.logLevel = old_level;
            if (child is null)
            {
                continue;
            }
            try {
                auto subpackage_visitor = new InsideNamespaceTranslator(this_namespace_path);
                subpackage_visitor.visit(child);

                if (subpackage_visitor.last_result && child.shouldEmit)
                {
                    placeIntoTargetModule(child, subpackage_visitor.last_result, this_namespace_path);
                }
            }
            catch (Exception exc)
            {
                stderr.writeln("ERROR: ", exc.msg);
            }
        }
        trace("Exiting translateNamespace");
    }

    extern(C++) override
    void visitNamespace(unknown.NamespaceDeclaration cppDecl)
    {
        translateNamespace(cppDecl);
        last_result = null;
    }

    private void addCppLinkageAttribute(T)(T declaration)
    {
        declaration.linkage = new dast.CppLinkageAttribute(namespace_path);
    }

    class IsRecord : unknown.DeclarationVisitor
    {
        // TODO when dmd issues #14020 is fixed, use a BlackHole instead
        override extern(C++) public void visitFunction(unknown.FunctionDeclaration node) { }

        override extern(C++) public void visitNamespace(unknown.NamespaceDeclaration node) { }

        override extern(C++) public void visitTypedef(unknown.TypedefDeclaration node) { }

        override extern(C++) public void visitEnum(unknown.EnumDeclaration node) { }

        override extern(C++) public void visitField(unknown.FieldDeclaration node) { }

        override extern(C++) public void visitEnumConstant(unknown.EnumConstantDeclaration node) { }

        override extern(C++) public void visitUnion(unknown.UnionDeclaration node) { }

        override extern(C++) public void visitMethod(unknown.MethodDeclaration node) { }

        override extern(C++) public void visitConstructor(unknown.ConstructorDeclaration node) { }

        override extern(C++) public void visitDestructor(unknown.DestructorDeclaration node) { }

        override extern(C++) public void visitArgument(unknown.ArgumentDeclaration node) { }

        override extern(C++) public void visitVariable(unknown.VariableDeclaration node) { }

        override extern(C++) public void visitUnwrappable(unknown.UnwrappableDeclaration node) { }

        override extern(C++) public void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration node) { }

        override extern(C++) public void visitTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration node) { }

        override extern(C++) public void visitUsingAliasTemplate(unknown.UsingAliasTemplateDeclaration node) { }
        // END BlackHole workaround

        public bool result;
        public unknown.RecordDeclaration outer;
        this(unknown.RecordDeclaration o)
        {
            result = false;
            outer = o;
        }
        override
        extern(C++) void visitRecord(unknown.RecordDeclaration inner)
        {
            if (binder.toDString(inner.getSourceName()) != binder.toDString(outer.getSourceName()))
                return;

            if (inner.getChildren().empty())
                result = true;
        }

        override
        extern(C++) void visitSpecializedRecord(unknown.SpecializedRecordDeclaration inner)
        {
            visitRecord(inner);
        }

        override
        extern(C++) void visitRecordTemplate(unknown.RecordTemplateDeclaration inner)
        {
            visitRecord(inner);
        }
    }
    // The clang AST has an extra record inside of each struct that appears spurious
    // struct A {
    //     void methodOnA();
    //     struct A { }; <- What's this for?
    // We filter this out
    private bool isEmptyDuplicateStructThingy(unknown.RecordDeclaration outer, unknown.Declaration inner)
    {
        auto visitor = new IsRecord(outer);
        inner.visit(visitor);
        return visitor.result;
    }

    private void translateStructBody
        (SubdeclarationVisitor, SourceDeclaration, TargetDeclaration)
        (SourceDeclaration cppDecl, TargetDeclaration result)
    {
        foreach (child; cppDecl.getChildren())
        {
            try {
                // FIXME the check for whether or not to bind shouldn't be made
                // everywhere; there should be a good, common place for it
                // At some point after I converted getChildren() to be a range,
                // the range stopped being able to lookup my metadata for the
                // EmptyDuplicateStructThingy, so it may return null now
                if (!child || !child.isWrappable())
                {
                    continue;
                }
                static if (__traits(compiles, isEmptyDuplicateStructThingy(cppDecl, child)))
                {
                    if (isEmptyDuplicateStructThingy(cppDecl, child))
                    {
                        continue;
                    }
                }

                // If we already translated the child, then skip it
                if (auto ptr = cast(void*)child in translated)
                {
                    if (*ptr == result)// If the child is me
                        // Not really clear on how this happens, but it does
                    {
                        continue;
                    }
                    result.addDeclaration(*ptr);
                    continue;
                }

                auto visitor = new SubdeclarationVisitor(namespace_path);
                unknown.Declaration decl = child;
                try {
                    visitor.visit(decl);
                }
                catch(RefTypeException e)
                {
                    e.declaration = decl;
                    throw e;
                }
                if (visitor.last_result.length && child.shouldEmit())
                {
                    try {
                        each!(d => d.visibility = translateVisibility(child))(visitor.last_result[]);
                    }
                    catch (Exception e)
                    {
                        // catch when visibility is unset.
                        // FIXME is this the right thing?
                        each!(d => d.visibility = dast.Visibility.Public)(visitor.last_result[]);
                    }
                    result.addDeclarations(visitor.last_result);
                }
            }
            catch (Exception exc)
            {
                //stderr.writeln("ERROR: ", exc.msg);
            }
        }
    }

    void translateAllBaseClasses(unknown.RecordDeclaration cppDecl, dast.InterfaceDeclaration result)
    {
        foreach (superclass; cppDecl.getSuperclassRange())
        {
            if (superclass.visibility != unknown.Visibility.PUBLIC)
            {
                // We can safely ignore these since they are not exposed
                // outside the class I suppose it would be a problem since
                // sublcasses on the D side cannot see the methods in the
                // superclass, but that's an acceptable loss for now
                continue;
            }
            if (superclass.isVirtual)
            {
                throw new Exception("Don't know how to translate virtual inheritance of interfaces.");
            }
            // Do the translation before checking if it's an interface because
            // the translation will force the type to pick a strategy
            dast.Type superType = translateType(superclass.base, QualifierSet.init);
            // FIXME cannot handle arbitrary replacement of superclasses
            if (superclass.base.getStrategy() != unknown.Strategy.INTERFACE
                    && superclass.base.getStrategy() != unknown.Strategy.REPLACE)
            {
                throw new Exception("Superclass of an interface (" ~ binder.toDString(cppDecl.getSourceName()) ~") is not an interface.");
            }

            // TODO convince the type system that superType is an interface
            result.addBaseType(superType);
        }
    }

    TargetType buildStruct(TargetType)(
            unknown.RecordDeclaration cppDecl,
            string name,
            dast.TemplateArgumentList template_params)
    {
        trace("Entering");
        scope(exit) trace("Exiting");

        auto result = CHECK_FOR_DECL!(TargetType)(cppDecl);
        if (result !is null)
        {
            info("Short-circuiting building the struct for ", name, " @0x", cast(void*)cppDecl, ".");
        }
        else
        {
            info("Long-circuiting building the struct for ", name, " @0x", cast(void*)cppDecl, ".");
            result = registerDeclaration!(TargetType)(cppDecl);
        }
        info("Building struct @0x", cast(void*)result);

        result.name = name;
        result.templateArguments = template_params;
        if (cast(void*)cppDecl in translated)
        {
            info("inserted the declaration into the translated AA");
        }
        else
        {
            info("DID NOT insert the declaration into the translated AA");
        }

        // Set the linkage attributes for this struct
        // This only matters for methods
        // FIXME should decide on C linkage sometimes, right?
        addCppLinkageAttribute(result);

        /*
         * I need to create a field, then "alias this field",
         * FIXME But, I need to make sure the field doesn't collide with anything.
         */
        unknown.SuperclassRange all_superclasses = cppDecl.getSuperclassRange();
        if (!all_superclasses.empty())
        {
            unknown.Superclass* superclass = all_superclasses.front();
            if (superclass.isVirtual)
            {
                throw new Exception("Don't know how to translate virtual inheritance of structs.");
            }
            dast.Type superType = translateType(superclass.base, QualifierSet.init);
            if (superclass.base.getStrategy() != unknown.Strategy.STRUCT)
            {
                throw new Exception("Superclass of a struct (" ~ binder.toDString(cppDecl.getSourceName()) ~ ") is not a struct.");
            }

            auto fieldDeclaration = new dast.VariableDeclaration();
            fieldDeclaration.name = "_superclass";
            fieldDeclaration.type = superType;
            result.addField(fieldDeclaration);

            if (superclass.visibility == unknown.Visibility.PUBLIC)
            {
                auto baseAlias = new dast.AliasThisDeclaration();
                baseAlias.target = fieldDeclaration;
                result.addClassLevelDeclaration(baseAlias);
            }

            all_superclasses.popFront();
            if (!all_superclasses.empty())
            {
                throw new Exception("Cannot translate multiple inheritance of structs without multiple alias this.");
                // FIXME I could just put all the components in as fields and generate
                // methods that call out to those as a workaround for now.
            }
        }

        translateStructBody!(StructBodyTranslator!(VirtualBehavior.FORBIDDEN, Flag!"fields".yes))(cppDecl, result);

        return result;
    }

    TargetType buildInterface(TargetType)(
            unknown.RecordDeclaration cppDecl,
            string name,
            dast.TemplateArgumentList template_params)
    {
        auto result = CHECK_FOR_DECL!(TargetType)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(TargetType)(cppDecl);
        }

        result.name = name;
        result.templateArguments = template_params;

        // Set the linkage attributes for this interface
        // This only matters for methods
        addCppLinkageAttribute(result);

        // Find the superclasses of this interface
        translateAllBaseClasses(cppDecl, result);

        translateStructBody!(StructBodyTranslator!(VirtualBehavior.ALLOWED, Flag!"fields".no))(cppDecl, result);

        return result;
    }

    dast.SpecializedInterfaceDeclaration buildSpecializedInterface(
            unknown.RecordDeclaration cppDecl,
            string name,
            dast.TemplateArgumentList template_params,
            dast.TemplateArgumentInstanceList template_values)
    {
        auto result = CHECK_FOR_DECL!(dast.SpecializedInterfaceDeclaration)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(dast.SpecializedInterfaceDeclaration)(cppDecl);
        }

        result.name = name;
        result.templateArguments = template_params;
        result.templateArgumentValues = template_values;

        // Set the linkage attributes for this interface
        // This only matters for methods
        addCppLinkageAttribute(result);

        // Find the superclasses of this interface
        translateAllBaseClasses(cppDecl, result);

        translateStructBody!(StructBodyTranslator!(VirtualBehavior.ALLOWED, Flag!"fields".no))(cppDecl, result);

        return result;
    }

    void buildRecord(
            unknown.RecordDeclaration cppDecl,
            string name,
            dast.TemplateArgumentList template_params)
    {
        alias StructType    = dast.StructDeclaration;
        alias InterfaceType = dast.InterfaceDeclaration;
        alias determineStrategyFunc = determineRecordTemplateStrategy;

        trace("Entering");
        scope(exit) trace("Exiting");
        if (cppDecl.getDefinition() !is cppDecl)
        {
            info("Skipping this cppDecl for ", name, " because it is not a definition.");
            return;
        }
        determineRecordStrategy(cppDecl.getRecordType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                info("Building record using strategy STRUCT.");
                auto result = buildStruct!(StructType)(cppDecl, name, template_params);
                break;
            case unknown.Strategy.INTERFACE:
                info("Building record using strategy INTERFACE.");
                buildInterface!(InterfaceType)(cppDecl, name, template_params);
                break;
            case unknown.Strategy.REPLACE:
                info("Skipping build because the strategy is REPLACE.");
                break;
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate records using strategies other than REPLACE, STRUCT, and INTERFACE yet.");
        }

    }

    dast.Declaration buildSpecializedRecord(
            unknown.SpecializedRecordDeclaration cppDecl,
            string name,
            dast.TemplateArgumentList template_params,
            dast.TemplateArgumentInstanceList template_values)
    {
        trace("Entering");
        scope(exit) trace("Exiting");
        if (cppDecl.getDefinition() !is cppDecl)
        {
            info("Skipping this cppDecl for ", name, " because it is not a definition.");
            return null; // TODO?
        }
        determineRecordStrategy(cppDecl.getRecordType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                info("Building record using strategy STRUCT.");
                auto result = buildStruct!(dast.SpecializedStructDeclaration)(cppDecl, name, template_params);
                result.templateArgumentValues = template_values;
                result.shouldEmit_ = cppDecl.isExplicit();
                return result;
            case unknown.Strategy.INTERFACE:
                info("Building record using strategy INTERFACE.");
                auto result = buildInterface!(dast.SpecializedInterfaceDeclaration)(cppDecl, name, template_params);
                result.templateArgumentValues = template_values;
                result.shouldEmit_ = cppDecl.isExplicit();
                return result;
            case unknown.Strategy.REPLACE:
                info("Skipping build because the strategy is REPLACE.");
                return null; // TODO?
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate records using strategies other than REPLACE, STRUCT, and INTERFACE yet.");
        }

    }

    extern(C++) override
    void visitRecord(unknown.RecordDeclaration cppDecl)
    {
        trace("Entering TranslatorVisitor.visitRecord()");
        scope(exit) trace("Exiting TranslatorVisitor.visitRecord()");
        string name = nameFromDecl(cppDecl);
        info("Translating record named ", name, " for cppDecl @", cast(void*)cppDecl);

        dast.TemplateArgumentList arg_list;
        buildRecord(cppDecl, name, arg_list);
        // Records using the replacement strategy don't produce a result
        auto ptr = cast(void*)cppDecl in translated;
        if (ptr && (!((*ptr) in placedDeclarations) || placedDeclarations[*ptr] == 0))
        {
            last_result = [*ptr];
        }
    }

    extern(C++) override
    void visitRecordTemplate(unknown.RecordTemplateDeclaration cppDecl)
    {
        trace("Entering TranslatorVisitor.visitRecordTemplate()");
        scope(exit) trace("Exiting TranslatorVisit.visitRecordTemplate()");

        string name = nameFromDecl(cppDecl);
        dast.TemplateArgumentList templateParameters = translateTemplateParameters(cppDecl);

        {
            buildRecord(cppDecl, name, templateParameters);

            // Records using the replacement strategy don't produce a result
            if (auto ptr = cast(void*)cppDecl in translated)
            {
                last_result = [*ptr];
            }
        }

        // Make symbols for all of the specializations
        // This is done so that the symbols inside the specialization have
        // proper paths; the declarations themselves should not be emitted.
        foreach (unknown.SpecializedRecordDeclaration special; cppDecl.getSpecializationRange())
        {
            try {
                last_result ~= [translateSpecializedRecord(special)];
            }
            catch(Exception e)
            {
                //special.dump();
                stderr.writeln("ERROR: ", e.msg);
            }
        }

    }

    dast.Declaration translateSpecializedRecord(unknown.SpecializedRecordDeclaration cppDecl)
    {
        dast.TemplateArgumentList templateParameters = translateTemplateParameters(cppDecl.getGenericDeclaration());
        // See note in visitRecordTemplate about why these are not emitted
        // via last_result
        dast.TemplateArgumentInstanceList templateArgumentValues = translateTemplateArguments(cppDecl);

        // FIXME this call
        return buildSpecializedRecord(cppDecl, nameFromDecl(cppDecl), templateParameters, templateArgumentValues);
    }

    extern(C++) override
    void visitSpecializedRecord(unknown.SpecializedRecordDeclaration cppDecl)
    {
        translateSpecializedRecord(cppDecl);
    }

    dast.AliasTypeDeclaration translateTypedef(unknown.TypedefDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.AliasTypeDeclaration)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(dast.AliasTypeDeclaration)(cppDecl);
        }

        addCppLinkageAttribute(result);
        result.name = nameFromDecl(cppDecl);
        result.type = translateType(cppDecl.getTargetType(), QualifierSet.init);

        return result;
    }
    extern(C++) override
    void visitTypedef(unknown.TypedefDeclaration cppDecl)
    {
        translateTypedef(cppDecl);
        last_result = [translated[cast(void*)cppDecl]];
    }

    // FIXME overlap with visitRecordTemplate
    extern(C++) override
    void visitUsingAliasTemplate(unknown.UsingAliasTemplateDeclaration cppDecl)
    {
        trace("Entering visitUsingAliasTemplate");
        scope(exit) trace("Exiting visitUsingAliasTemplate");

        string name = nameFromDecl(cppDecl);
        trace("Translating UsingAliasTemplateDeclaration: ", name);
        // FIXME templateParameters is unused!!
        dast.TemplateArgumentDeclaration[] templateParameters = translateTemplateParameters(cppDecl);

        {
            translateTypedef(cppDecl);

            if (auto ptr = cast(void*)cppDecl in translated)
            {
                last_result = [*ptr];
            }
        }
    }

    dast.EnumDeclaration translateEnum(unknown.EnumDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.EnumDeclaration)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(dast.EnumDeclaration)(cppDecl);
        }

        result.name = nameFromDecl(cppDecl);

        unknown.Type cppType = cppDecl.getMemberType();
        result.type = translateType(cppType, QualifierSet.init);


        // visit and translate all of the constants
        foreach (child; cppDecl.getChildren())
        {
            unknown.EnumConstantDeclaration constant = cast(unknown.EnumConstantDeclaration)child;
            if (constant is null)
            {
                stdout.write("Error translating enum constant.\n");
                continue;
            }

            result.members ~= [translateEnumConstant(constant)];
        }

        return result;
    }
    extern(C++) override void visitEnum(unknown.EnumDeclaration cppDecl)
    {
        translateEnum(cppDecl);
        last_result = [translated[cast(void*)cppDecl]];
    }

    dast.EnumMember translateEnumConstant(unknown.EnumConstantDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.EnumMember)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(dast.EnumMember)(cppDecl);
        }

        result.name = nameFromDecl(cppDecl); // TODO remove prefix

        result.value = new dast.IntegerLiteralExpression(cppDecl.getLLValue);

        return result;
    }
    extern(C++) override void visitEnumConstant(unknown.EnumConstantDeclaration)
    {
        // Getting here means that there is an enum constant declaration
        // outside of an enum declaration, since visitEnum calls
        // translateEnumConstant directly.
        throw new Error("Attempted to translate an enum constant directly, instead of via an enum.");
    }

    extern(C++) override void visitField(unknown.FieldDeclaration)
    {
        // Getting here means that there is a field declaration
        // outside of a record declaration, since the struct / interface building
        // functions call translateField directly.
        throw new Error("Attempted to translate a field directly, instead of via a record.");
    }

    dast.UnionDeclaration translateUnion(unknown.UnionDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.UnionDeclaration)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(dast.UnionDeclaration)(cppDecl);
        }
        if (!cppDecl.isAnonymous)
        {
            result.name = nameFromDecl(cppDecl);
        }

        // If the union is anonymous, then there are not any references to it
        // in C++, so it's OK to produce a symbol that doesn't make total
        // sense, since it will never be used for that purpose.  It may be used
        // to refer to members, however, so we do need it.
        // ^ TODO does this comment still apply with my new AST?

        addCppLinkageAttribute(result);

        if (cppDecl.getTemplateArgumentCount() > 0)
        {
            // This cast always succeeds because we know there are template
            // arguments.
            auto templateDecl = cast(unknown.UnionTemplateDeclaration)cppDecl;
            result.templateArguments = translateTemplateParameters(templateDecl);
        }

        translateStructBody!(StructBodyTranslator!(VirtualBehavior.FORBIDDEN, Flag!"fields".yes))(cppDecl, result);
        return result;
    }
    extern(C++) override void visitUnion(unknown.UnionDeclaration cppDecl)
    {
        translateUnion(cppDecl);
        last_result = [translated[cast(void*)cppDecl]];
    }


    extern(C++) override void visitMethod(unknown.MethodDeclaration)
    {
        // Getting here means that there is a method declaration
        // outside of a record declaration, since the struct / interface building
        // functions call translateMethod directly.
        //assert(0);
        //throw new Exception("Attempting to translate a method as if it were top level, but methods are never top level.");
    }
    extern(C++) override void visitConstructor(unknown.ConstructorDeclaration)
    {
        // the C++ interface page on dlang.org says that D cannot call constructors
    }
    extern(C++) override void visitDestructor(unknown.DestructorDeclaration)
    {
        // the C++ interface page on dlang.org says that D cannot call destructors
    }

    dast.Argument translateArgument(unknown.ArgumentDeclaration cppDecl)
    {
        /*auto short_circuit = CHECK_FOR_DECL!(std.d.ast.Parameter)(cppDecl);
        if (short_circuit !is null) return short_circuit;*/
        // TODO put into translate AA

        auto arg = new dast.Argument();
        arg.name = nameFromDecl(cppDecl);

        unknown.Type cppType = cppDecl.getType();

        try {
            arg.type = translateType(cppType, QualifierSet.init);
        }
        catch (RefTypeException e)
        {
            unknown.Type targetType = handleReferenceType(cppType);
            if (targetType)
            {
                arg.type = translateType(targetType, QualifierSet.init);
                arg.ref_ = Yes.ref_;
            }
            else
            {
                throw e;
            }
        }

        return arg;
    }
    extern(C++) override void visitArgument(unknown.ArgumentDeclaration cppDecl)
    {
        throw new Exception("Attempting to translate an argument as if it were top level, but arguments are never top level.");
    }

    dast.VariableDeclaration translateVariable(unknown.VariableDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.VariableDeclaration)(cppDecl);

        if (result is null)
        {
            result = registerDeclaration!(dast.VariableDeclaration)(cppDecl);
        }

        result.name = nameFromDecl(cppDecl);

        addCppLinkageAttribute(result);

        result.type = translateType(cppDecl.getType(), QualifierSet.init);

        return result;
    }
    extern(C++) override void visitVariable(unknown.VariableDeclaration cppDecl)
    {
        last_result = [translateVariable(cppDecl)];
    }
    extern(C++) override void visitUnwrappable(unknown.UnwrappableDeclaration)
    {
        // Cannot wrap unwrappable declarations, ;)
    }

    // This should only ever be called when putting together the argument list
    // for a template, so we don't need to check for duplicates
    dast.TemplateTypeArgumentDeclaration translateTemplateTypeArgument(unknown.TemplateArgumentIterator cpp_iter)
    {
        trace("Entering TranslatorVisitor.translateTemplateTypeArgument()");
        scope(exit) trace("Exiting TranslatorVisitor.translateTemplateTypeArgument()");

        unknown.TemplateTypeArgumentDeclaration cppDecl = cpp_iter.getType();
        auto result = CHECK_FOR_DECL!(dast.TemplateTypeArgumentDeclaration)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(dast.TemplateTypeArgumentDeclaration)(cppDecl);
        }
        for (int decl_index = 0; decl_index < cpp_iter.getDefinitionCount(); ++decl_index)
        {
            unknown.TemplateTypeArgumentDeclaration nameDecl = cpp_iter.getType();
            translated[cast(void*)nameDecl] = result;
            if (result.name.length == 0)
            {
                result.name = nameFromDecl(nameDecl);
            }
            cpp_iter.switchDefinition();
        }

        if (cppDecl.hasDefaultType())
        {
            result.defaultType = translateType(cppDecl.getDefaultType(), QualifierSet.init);
        }

        return result;
    }

    extern(C++) override void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration cppDecl)
    {
        throw new Exception("Attempting to translate a template type argument not via the template itself.");
    }

    dast.TemplateValueArgumentDeclaration translateTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.TemplateValueArgumentDeclaration)(cppDecl);
        if (result is null)
        {
            result = registerDeclaration!(dast.TemplateValueArgumentDeclaration)(cppDecl);
        }
        result.type = translateType(cppDecl.getType(), QualifierSet.init);
        result.name = nameFromDecl(cppDecl);

        if (cppDecl.hasDefaultArgument())
        {
            try {
                unknown.Expression expr = cppDecl.getDefaultArgument();
                result.defaultValue = translateExpression(expr);
            }
            catch (translate.expr.ExpressionTranslationFailure e)
            {
                // FIXME If there's a problem translating the default value of
                // the argument, then we'll just leave it out.  Later
                // instantiations will have to specify the arguments and code
                // will break, but I do not anticipate silently changing
                // anything.
                result.defaultValue = null;
            }
        }

        return result;
    }
    extern(C++) override void visitTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration cppDecl)
    {
        throw new Exception("Attempting to translate a template type argument not via the template itself.");
    }

    dast.TemplateArgumentDeclaration translateTemplateArgument(unknown.TemplateArgumentIterator iter)
    {
        final switch (iter.getKind())
        {
            case unknown.TemplateArgumentIterator.Kind.Type:
                return translateTemplateTypeArgument(iter);
            case unknown.TemplateArgumentIterator.Kind.NonType:
                return translateTemplateNonTypeArgument(iter.getNonType());
        }
    }

    dast.TemplateArgumentDeclaration[] translateTemplateParameters(Declaration)(Declaration cppDecl)
    {
        dast.TemplateArgumentDeclaration[] result = [];

        for (unknown.TemplateArgumentIterator iter = cppDecl.getTemplateArgumentBegin(),
                end = cppDecl.getTemplateArgumentEnd();
             !iter.equals(end);
             iter.advance() )
        {
            auto current = translateTemplateArgument(iter);
            result ~= [current];
        }

        return result;
    }

    //Translates a list of specific template argument instances
    dast.TemplateArgumentInstanceList translateTemplateArguments(Declaration)(Declaration cppDecl)
    {
        dast.TemplateArgumentInstance[] result = [];

        for (unknown.TemplateArgumentInstanceIterator iter = cppDecl.getTemplateArgumentBegin(),
                end = cppDecl.getTemplateArgumentEnd();
             !iter.equals(end);
             iter.advance() )
        {
            dast.TemplateArgumentInstance current;
            final switch (iter.getKind())
            {
                case unknown.TemplateArgumentInstanceIterator.Kind.Type:
                    try {
                        current = new dast.TemplateTypeArgumentInstance(translateType(iter.getType(), QualifierSet.init));
                    }
                    catch(RefTypeException e)
                    {
                        stderr.writeln("Template argument is a reference...");
                        throw e;
                    }
                    break;
                case unknown.TemplateArgumentInstanceIterator.Kind.Integer:
                    auto constant = new dast.IntegerLiteralExpression(iter.getInteger());
                    current = new dast.TemplateValueArgumentInstance(constant);
                    break;
                case unknown.TemplateArgumentInstanceIterator.Kind.Expression:
                    current = new dast.TemplateValueArgumentInstance(translateExpression(iter.getExpression()));
                    break;
                case unknown.TemplateArgumentInstanceIterator.Kind.Pack:
                    //iter.dumpPackInfo();
                    throw new Exception("Cannot translate template Pack argument");
            }
            result ~= [current];
        }

        return dast.TemplateArgumentInstanceList(result);
    }
}

class GlobalTranslator : TranslatorVisitor
{
    this()
    {
        super();
    }

    override
    dast.VariableDeclaration translateVariable(unknown.VariableDeclaration variable)
    {
        dast.VariableDeclaration result = super.translateVariable(variable);
        // If the variable wasn't extern in the C++, it is in the D
        result.extern_ = true;
        return result;
    }
}

// Strips "extern(C++, ns)" off of declarations inside of it
class InsideNamespaceTranslator : TranslatorVisitor
{
    this(string namespace_path)
    {
        super(namespace_path);
    }

    override
    dast.VariableDeclaration translateVariable(unknown.VariableDeclaration variable)
    {
        dast.VariableDeclaration result = super.translateVariable(variable);
        // FIXME this is a bit blunt
        result.linkage = null;
        return result;
    }

    override
    dast.FunctionDeclaration translateFunction(unknown.FunctionDeclaration variable)
    {
        dast.FunctionDeclaration result = super.translateFunction(variable);
        // FIXME this is a bit blunt
        result.linkage = null;
        return result;
    }
}

// TODO Need a way to communicate whether an unwrappable declaration should be
// ignored (with an error message, obviously) or make the parent unwrappable.
class StructBodyTranslator
    // I want to use a Flag!"fields" instead of a bool here, but
    // that causes an ICE that I can't easily reduce.
      (VirtualBehavior vBehavior, bool fieldsAllowed)
    : TranslatorVisitor
{
    this(string nsp/+, DeferredSymbol pip+/)
    {
        super(nsp/+, pip+/);
    }

    override
    dast.VariableDeclaration translateVariable(unknown.VariableDeclaration cppDecl)
    {
        auto result = TranslatorVisitor.translateVariable(cppDecl);
        result.static_ = true;
        return result;
    }

    dast.FunctionDeclaration translateMethod(unknown.MethodDeclaration cppDecl)
    {
        auto result = CHECK_FOR_DECL!(dast.FunctionDeclaration)(cppDecl);
        if (result !is null) return result;

        if (cppDecl.isOverloadedOperator())
        {
            throw new OverloadedOperatorError();
        }

        if (cppDecl.isStatic())
        {
            result = registerDeclaration!(dast.FunctionDeclaration)(cppDecl);
            // FIXME add to parent as static method
        }
        else
        {
            auto method = registerDeclaration!(dast.MethodDeclaration)(cppDecl);
            if (cppDecl.isConst())
            {
                method.const_ = Yes.const_;
            }

            if (cppDecl.isVirtual())
            {
                static if (vBehavior == VirtualBehavior.FORBIDDEN)
                {
                    throw new Exception("Methods on structs cannot be virtual!");
                    // FIXME this message may not always be correct
                }
                else
                {
                    method.virtual_ = Yes.virtual_;
                }
                // virtual is implied by context i.e. must be in class, interface,
                // then it's by default, so no attribute here
            }
            else {
                static if (vBehavior == VirtualBehavior.REQUIRED)
                {
                    // FIXME this message may not always be correct
                    throw new Exception("Methods on interfaces must be virtual!");
                }
                else
                {
                    method.virtual_ = No.virtual_;
                }
            }

            result = method;
        }

        if (cppDecl.getTargetName().size())
        {
            result.name = nameFromDecl(cppDecl);
        }
        else
        {
            throw new Exception("Method declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        try {
            result.setReturnType(translateType(cppDecl.getReturnType(), QualifierSet.init));
        }
        catch (RefTypeException e)
        {
            // Make sure that this isn't a ref farther down, since the ref
            // modifier can only be applied to the parameter
            unknown.Type targetType = handleReferenceType(cppDecl.getReturnType());

            if (targetType)
            {
                result.setReturnType(translateType(targetType, QualifierSet.init), Yes.ref_);
            }
            else
            {
                throw e;
            }
        }
        if (cppDecl.getVisibility() == unknown.Visibility.UNSET)
        {
            //cppDecl.dump();
        }

        for (unknown.ArgumentIterator arg_iter = cppDecl.getArgumentBegin(),
                arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance() )
        {
            result.arguments ~= [translateArgument(arg_iter.get())];
        }
        return result;
    }

    extern(C++) override void visitMethod(unknown.MethodDeclaration cpp_method)
    {
        if (!cpp_method || !cpp_method.isWrappable())
        {
            last_result = null;
            return;
        }

        dast.FunctionDeclaration method = translateMethod(cpp_method);

        bool shouldInsert = true;
        static if (vBehavior != VirtualBehavior.FORBIDDEN)
        {
            bool no_bound_overrides = true;
            for (unknown.OverriddenMethodIterator override_iter = cpp_method.getOverriddenBegin(),
                    override_finish = cpp_method.getOverriddenEnd();
                 !override_iter.equals(override_finish) && no_bound_overrides;
                 override_iter.advance() )
            {
                unknown.MethodDeclaration superMethod = override_iter.get();
                if (superMethod.shouldEmit())
                {
                    no_bound_overrides = false;
                }
            }
            shouldInsert = no_bound_overrides;
        }
        shouldInsert = shouldInsert && cpp_method.shouldEmit();

        if (shouldInsert)
        {
            last_result = [method];
        }
        else
        {
            last_result = [];
        }
    }

    static if (fieldsAllowed)
    {
        // TODO indicate to parent if this is a class / member variable
        dast.VariableDeclaration translateField(unknown.FieldDeclaration cppDecl)
        {
            auto result = CHECK_FOR_DECL!(dast.VariableDeclaration)(cppDecl);
            if (result !is null) return result;

            try {
                result = registerDeclaration!(dast.VariableDeclaration)(cppDecl);
                result.type = translateType(cppDecl.getType(), QualifierSet.init);

                result.name = nameFromDecl(cppDecl);

                return result;
            }
            catch (RefTypeException e)
            {
                e.declaration = cppDecl;
                throw e;
            }
        }

        extern(C++) override void visitField(unknown.FieldDeclaration cppDecl)
        {
            translateField(cppDecl);
            last_result = [translated[cast(void*)cppDecl]];
        }
    }
    else
    {
        extern(C++) override void visitField(unknown.FieldDeclaration cppDecl)
        {
            // We're an interface, so skip fields.
        }
    }
}

private dast.Module findTargetModule(unknown.Declaration declaration)
{
    string target_module = binder.toDString(declaration.getTargetModule());
    if (target_module.length == 0)
    {
        target_module = "unknown";
    }
    else
    {
        // Root package is named empty, so target modules may start with '.', as in
        // .std.stdio
        // '.' messes with the lookup, so take it out if it's there
        if (target_module[0] == '.')
        {
            target_module = target_module[1 ..$];
        }
    }
    return rootPackage.getOrCreateModulePath(target_module);
}

private void placeIntoTargetModule(
    unknown.Declaration declaration,
    dast.Declaration[] translation_list,
    string namespace_path)
{
    foreach (translation; translation_list)
    {
        // FIXME sometimes this gets called multiple times on the same declaration,
        // so it will get output multiple times, which is clearly wrong
        // It happens because there are multiple declarations of the same type
        // (e.g. forward and normal), that have the same translation
        if (translation)
        {
            if (translation in placedDeclarations)
            {
                info("Already placed cpp decl ", binder.toDString(declaration.getSourceName()), " @", cast(void*)declaration);
                return;
            }

            destination.addDeclaration(translation, namespace_path);
            placedDeclarations[translation] = 1;
        }
        else
        {
            info("No translation for declaration @", cast(void*)declaration);
        }
    }
}

// This function is responsible for building just enough of a D AST to
// continue.  That means: it picks the right type of AST node, but doesn't
// name it or place it anywhere.
dast.Type startDeclTypeBuild(unknown.Declaration cppDecl)
{
    if (auto decl_ptr = cast(void*)cppDecl in translated)
    {
        dast.Type result = cast(dast.Type)*decl_ptr;
        assert(result !is null);
        return result;
    }

    trace("Starting declaration build for cppDecl ", nameFromDecl(cppDecl), " @ 0x", cast(void*)cppDecl);
    auto visitor = new StarterVisitor();
    cppDecl.visit(visitor);
    if (visitor.result is null)
    {
        //cppDecl.dump();
        assert(visitor.result !is null);
    }
    return visitor.result;
}
// Inherit from DeclarationVisitor instead of TranslatorVisitor since we
// need to replace all the methods
class StarterVisitor : unknown.DeclarationVisitor
{
    public:
    dast.Type result;

    extern(C++) void visitFunction(unknown.FunctionDeclaration) { }
    extern(C++) void visitNamespace(unknown.NamespaceDeclaration) { }
    extern(C++) void visitField(unknown.FieldDeclaration) { }
    extern(C++) void visitEnumConstant(unknown.EnumConstantDeclaration) { }
    extern(C++) void visitMethod(unknown.MethodDeclaration) { }
    extern(C++) void visitConstructor(unknown.ConstructorDeclaration) { }
    extern(C++) void visitDestructor(unknown.DestructorDeclaration) { }
    extern(C++) void visitArgument(unknown.ArgumentDeclaration) { }
    extern(C++) void visitVariable(unknown.VariableDeclaration) { }
    extern(C++) void visitTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration) { }

    extern(C++) void visitRecord(unknown.RecordDeclaration cppDecl)
    {
        import dlang_decls : makeIdentifierOrTemplateChain;

        // FIXME copied from TranslatorVisitor.buildRecord
        trace("Entering");
        scope(exit) trace("Exiting");
        determineRecordStrategy(cppDecl.getRecordType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                info("Building record using strategy STRUCT.");
                result = registerDeclaration!(dast.StructDeclaration)(cppDecl);
                break;
            case unknown.Strategy.INTERFACE:
                info("Building record using strategy INTERFACE.");
                result = registerDeclaration!(dast.InterfaceDeclaration)(cppDecl);
                break;
            case unknown.Strategy.REPLACE:
                info("Skipping build because the strategy is REPLACE.");
                auto replacement = new dast.ReplacedType();
                replacement.fullyQualifiedName = makeIdentifierOrTemplateChain!"."(nameFromDecl(cppDecl));
                assert(replacement.fullyQualifiedName !is null);
                result = replacement;
                break;
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate records using strategies other than REPLACE, STRUCT, and INTERFACE yet.");
        }
    }
    extern(C++) void visitRecordTemplate(unknown.RecordTemplateDeclaration cppDecl)
    {
        alias StructType    = dast.StructDeclaration;
        alias InterfaceType = dast.InterfaceDeclaration;
        //static assert(is(dast.TemplateArgumentList : dast.TemplateArgumentList));
        determineRecordStrategy(cppDecl.getRecordType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                result = registerDeclaration!(StructType)(cppDecl);
                break;
            case unknown.Strategy.INTERFACE:
                result = registerDeclaration!(InterfaceType)(cppDecl);
                break;
            case unknown.Strategy.REPLACE:
                //cppDecl.dump();
                // Let's see if treating it as a struct works...
                // The plan is to not fill it in, but that pointers to it
                // should be "T*" rather than just "T" as for interfaces
                result = registerDeclaration!(StructType)(cppDecl);
                //assert(0);
                break;
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate records using strategies other than REPLACE, STRUCT, and INTERFACE yet.");
        }
    }
    extern(C++) void visitTypedef(unknown.TypedefDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.AliasTypeDeclaration)(cppDecl);
    }
    extern(C++) void visitEnum(unknown.EnumDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.EnumDeclaration)(cppDecl);
    }
    extern(C++) void visitUnion(unknown.UnionDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.UnionDeclaration)(cppDecl);
    }
    extern(C++) void visitSpecializedRecord(unknown.SpecializedRecordDeclaration cppDecl)
    {
        determineRecordStrategy(cppDecl.getRecordType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                info("Building specialized record using strategy STRUCT.");
                result = registerDeclaration!(dast.SpecializedStructDeclaration)(cppDecl);
                break;
            case unknown.Strategy.INTERFACE:
                info("Building specialized record using strategy INTERFACE.");
                result = registerDeclaration!(dast.SpecializedInterfaceDeclaration)(cppDecl);
                break;
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate specialized records using strategies other than STRUCT and INTERFACE yet.");
        }
    }
    extern(C++) void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.TemplateTypeArgumentDeclaration)(cppDecl);
    }
    extern(C++) void visitUsingAliasTemplate(unknown.UsingAliasTemplateDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.AliasTypeDeclaration)(cppDecl);
    }
    extern(C++) void visitUnwrappable(unknown.UnwrappableDeclaration)
    {
        assert(0);
    }
}

// This function is responsible for building just enough of a D AST to
// continue.  That means: it picks the right type of AST node, but doesn't
// name it or place it anywhere.
dast.Declaration startDeclBuild(unknown.Declaration cppDecl)
{
    if (auto decl_ptr = cast(void*)cppDecl in translated)
    {
        return *decl_ptr;
    }

    trace("Starting declaration build for cppDecl ", nameFromDecl(cppDecl), " @ 0x", cast(void*)cppDecl);
    auto visitor = new DeclarationStarterVisitor();
    cppDecl.visit(visitor);
    if (visitor.result is null)
    {
        assert(visitor.result !is null);
    }
    return visitor.result;
}
// Inherit from DeclarationVisitor instead of TranslatorVisitor since we
// need to replace all the methods
class DeclarationStarterVisitor : unknown.DeclarationVisitor
{
    public:
    dast.Declaration result;

    extern(C++) void visitFunction(unknown.FunctionDeclaration) { assert(0); }
    extern(C++) void visitNamespace(unknown.NamespaceDeclaration) { assert(0); }
    extern(C++) void visitField(unknown.FieldDeclaration) { assert(0); }
    extern(C++) void visitEnumConstant(unknown.EnumConstantDeclaration) { assert(0); }
    extern(C++) void visitMethod(unknown.MethodDeclaration) { assert(0); }
    extern(C++) void visitConstructor(unknown.ConstructorDeclaration) { assert(0); }
    extern(C++) void visitDestructor(unknown.DestructorDeclaration) { assert(0); }
    extern(C++) void visitArgument(unknown.ArgumentDeclaration) { assert(0); }
    extern(C++) void visitVariable(unknown.VariableDeclaration cppDecl)
    {
        // Need to check if this should be field, etc...
        result = registerDeclaration!(dast.VariableDeclaration)(cppDecl);
    }
    // FIXME this is going to interact poorly with the fact that all the lists
    // of template arguments share the same D declaration, I need to find a way
    // to find which argument list each template argument declaration came
    // from.
    extern(C++) void visitTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration cppDecl)
    {
        assert(0);
    }

    extern(C++) void visitRecord(unknown.RecordDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitRecordTemplate(unknown.RecordTemplateDeclaration)
    {
        // TODO fill this one in!
        assert(0);
    }
    extern(C++) void visitTypedef(unknown.TypedefDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitEnum(unknown.EnumDeclaration)
    {
        // TODO fill this one in!
        assert(0);
    }
    extern(C++) void visitUnion(unknown.UnionDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitSpecializedRecord(unknown.SpecializedRecordDeclaration)
    {
        // TODO fill this one in!
        assert(0);
    }
    extern(C++) void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitUsingAliasTemplate(unknown.UsingAliasTemplateDeclaration)
    {
        assert(0);
    }
    extern(C++) void visitUnwrappable(unknown.UnwrappableDeclaration)
    {
        assert(0);
    }
}
// This function is responsible for building just enough of a D AST to
// continue.  That means: it picks the right type of AST node, but doesn't
// name it or place it anywhere.
dast.Expression startDeclExprBuild(unknown.Declaration cppDecl)
{
    if (auto decl_ptr = cast(void*)cppDecl in translated)
    {
        dast.Expression result = cast(dast.Expression)*decl_ptr;
        assert(result !is null);
        return result;
    }

    trace("Starting declaration build for cppDecl ", nameFromDecl(cppDecl), " @ 0x", cast(void*)cppDecl);
    auto visitor = new ExpressionStarterVisitor();
    cppDecl.visit(visitor);
    if (visitor.result is null)
    {
        cppDecl.dump();
        assert(visitor.result !is null);
    }
    return visitor.result;
}
// Inherit from DeclarationVisitor instead of TranslatorVisitor since we
// need to replace all the methods
class ExpressionStarterVisitor : unknown.DeclarationVisitor
{
    public:
    dast.Expression result;

    extern(C++) void visitFunction(unknown.FunctionDeclaration) { assert(0); }
    extern(C++) void visitNamespace(unknown.NamespaceDeclaration) { assert(0); }
    extern(C++) void visitField(unknown.FieldDeclaration) { assert(0); }

    extern(C++) void visitEnumConstant(unknown.EnumConstantDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.EnumMember)(cppDecl);
    }

    extern(C++) void visitMethod(unknown.MethodDeclaration) { assert(0); }
    extern(C++) void visitConstructor(unknown.ConstructorDeclaration) { assert(0); }
    extern(C++) void visitDestructor(unknown.DestructorDeclaration) { assert(0); }
    extern(C++) void visitArgument(unknown.ArgumentDeclaration) { assert(0); }

    extern(C++) void visitVariable(unknown.VariableDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.VariableDeclaration)(cppDecl);
    }

    // FIXME this is going to interact poorly with the fact that all the lists
    // of template arguments share the same D declaration, I need to find a way
    // to find which argument list each template argument declaration came
    // from.
    extern(C++) void visitTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration cppDecl)
    {
        result = registerDeclaration!(dast.TemplateValueArgumentDeclaration)(cppDecl);
    }

    extern(C++) void visitRecord(unknown.RecordDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitRecordTemplate(unknown.RecordTemplateDeclaration)
    {
        // TODO fill this one in!
        assert(0);
    }
    extern(C++) void visitTypedef(unknown.TypedefDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitEnum(unknown.EnumDeclaration)
    {
        // TODO fill this one in!
        assert(0);
    }
    extern(C++) void visitUnion(unknown.UnionDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitSpecializedRecord(unknown.SpecializedRecordDeclaration)
    {
        // TODO fill this one in!
        assert(0);
    }
    extern(C++) void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration cppDecl)
    {
        assert(0);
    }
    extern(C++) void visitUsingAliasTemplate(unknown.UsingAliasTemplateDeclaration)
    {
        assert(0);
    }
    extern(C++) void visitUnwrappable(unknown.UnwrappableDeclaration)
    {
        assert(0);
    }
}

dast.Module destination;

dast.Module populateDAST(string output_module_name)
{
    // May cause problems because root package won't check for empty path.
    size_t array_len = 0;
    unknown.Declaration* freeDeclarations = null;
    unknown.arrayOfFreeDeclarations(&array_len, &freeDeclarations);

    destination = new dast.Module(output_module_name);

    for (size_t i = 0; i < array_len; ++i)
    {
        unknown.Declaration declaration = freeDeclarations[i];
        if (!declaration.isWrappable())
        {
            continue;
        }

        if (declaration.shouldEmit())
        {
            dast.Module mod = findTargetModule(declaration);
            // FIXME creates the module as a side effect of finding?
        }

        auto visitor = new GlobalTranslator();
        try {
            dast.Declaration[] translation;
            if (cast(void*)declaration !in translated)
            {
                visitor.visit(declaration);
                translation = visitor.last_result;
            }
            else
            {
                translation = [translated[cast(void*)declaration]];
            }

            // some items, such as namespaces, don't need to be placed into a module.
            // visiting them just translates their children and puts them in modules
            if (translation.length && declaration.shouldEmit)
            {
                placeIntoTargetModule(declaration, translation, "");
            }
        }
        catch (Exception exc)
        {
            stderr.writeln("ERROR: ", exc.msg);
        }

    }

    return destination;
}

void determineRecordStrategy(unknown.RecordType cppType)
{
    // There are some paths that don't come through determineStrategy,
    // so filter those out.
    if (cppType.getStrategy() != unknown.Strategy.UNKNOWN)
    {
        return;
    }

    // First algorithm:
    // If the record has any virtual functions, then map it as an interface,
    // otherwise keep it as a struct
    // This ignores things like the struct default constructor,
    // so it's not perfect

    unknown.RecordDeclaration cpp_decl = cppType.getRecordDeclaration();
    if (cpp_decl is null)
    {
        //cppType.dump();
        //stderr.writeln("Wrappable: ", cppType.isWrappable(false));
        throw new Exception("This type isn't wrappable, so I cannot pick a strategy.");
    }

    if (!cpp_decl.isCXXRecord())
    {
        cppType.setStrategy(unknown.Strategy.STRUCT);
    }
    else
    {
        if (!cpp_decl.hasDefinition())
        {
            stderr.writeln("WARNING: ", binder.toDString(cpp_decl.getSourceName()), " has no definition, so I cannot determine a translation strategy; choosing REPLACE.");
            cppType.chooseReplaceStrategy(binder.toBinderString(""));
        }
        else if(cpp_decl.isDynamicClass())
        {
            cppType.setStrategy(unknown.Strategy.INTERFACE);
        }
        else
        {
            cppType.setStrategy(unknown.Strategy.STRUCT);
        }
    }
}

void determineRecordTemplateStrategy(unknown.RecordTemplateDeclaration cppTemplateDecl)
{
    if (!cppTemplateDecl.isCXXRecord()) // Is every template a CXXRecord?
    {
        cppTemplateDecl.getType().setStrategy(unknown.Strategy.STRUCT);
    }
    else if (!cppTemplateDecl.hasDefinition())
    {
        // Try to decide from the specialization declarations
        unknown.SpecializedRecordRange range = cppTemplateDecl.getSpecializationRange();
        foreach (unknown.SpecializedRecordDeclaration special; range)
        {
            unknown.RecordType specialType = cast(unknown.RecordType)special.getType();
            assert(specialType !is null); // above is not a dynamic_cast, so this always succeeds
            determineRecordStrategy(specialType);
            if (specialType.getStrategy() == unknown.Strategy.INTERFACE)
            {
                cppTemplateDecl.getType().setStrategy(unknown.Strategy.INTERFACE);
                break;
            }
            else if (specialType.getStrategy() == unknown.Strategy.STRUCT)
            {
                cppTemplateDecl.getType().setStrategy(unknown.Strategy.STRUCT);
                break;
            }
            // FIXME should make sure that all specialiations agree on the strategy
        }
        // If none of the specializations were either INTERFACE or STRUCT
        if (cppTemplateDecl.getType().getStrategy() == unknown.Strategy.UNKNOWN)
        {
            stderr.writeln("WARNING: ", binder.toDString(cppTemplateDecl.getSourceName()), " has no definition, so I cannot determine a translation strategy; choosing REPLACE.");
            cppTemplateDecl.getType().chooseReplaceStrategy(binder.toBinderString(""));
        }
        stderr.writeln("Picked ", cppTemplateDecl.getType().getStrategy());
        //assert(0);
    }
    else if (cppTemplateDecl.isDynamicClass())
    {
        cppTemplateDecl.getType().setStrategy(unknown.Strategy.INTERFACE);
    }
    else
    {
        cppTemplateDecl.getType().setStrategy(unknown.Strategy.STRUCT);
    }
    /+stderr.writeln("got here!");
    stderr.writeln("cppType = ");
    cppType.dump();
    stderr.writeln("cpp_decl = ", cast(void*)cpp_decl);
    cpp_decl.dump();
    stderr.writeln("Template record = ", cast(void*)templateRecord);
    templateRecord.dump();
    assert(0);+/
}

class NoDefinitionException : Exception
{
    this(unknown.Declaration decl)
    {
      super(to!string(decl.getSourceName().c_str()) ~ " has no definition, so I cannot determine a translation strategy.");
    }
}

void determineTemplateStrategy(unknown.Declaration genericCppDecl)
{
    class StrategyChoiceVisitor : unknown.DeclarationVisitor
    {
        public:
        mixin template assertImpl(string node) {
            mixin("override extern(C++) void visit"~node~"(unknown."~node~"Declaration cppDecl) { stderr.writeln(\"visiting "~node~"\"); cppDecl.dump(); assert(0); }");
        }
        mixin assertImpl!"Function";
        mixin assertImpl!"Namespace";
        mixin assertImpl!"Field";
        mixin assertImpl!"EnumConstant";
        mixin assertImpl!"Variable";
        mixin assertImpl!"Constructor";
        mixin assertImpl!"Destructor";
        mixin assertImpl!"TemplateTypeArgument";
        mixin assertImpl!"TemplateNonTypeArgument";
        mixin assertImpl!"Unwrappable";
        mixin assertImpl!"Argument";
        mixin assertImpl!"Method";
        mixin assertImpl!"Enum";
        mixin assertImpl!"Union";
        mixin assertImpl!"Typedef";
        mixin assertImpl!"Record";
        mixin assertImpl!"SpecializedRecord";
        override extern(C++) void visitUsingAliasTemplate(unknown.UsingAliasTemplateDeclaration cppDecl)
        {
            unknown.Type targetType = cppDecl.getTargetType();
            determineStrategy(targetType);
        }

        override extern(C++) void visitRecordTemplate(unknown.RecordTemplateDeclaration cppDecl)
        {
            determineRecordTemplateStrategy(cppDecl);
            //assert(0);
        }
    }

    auto visitor = new StrategyChoiceVisitor();
    genericCppDecl.visit(visitor);
}
