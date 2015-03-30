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

module translate.decls;

import std.array;
import std.conv : to;
import std.stdio : stdout, stderr;
import std.typecons : Flag;
import std.experimental.logger;

import std.d.ast;
import std.d.formatter : format;
import std.d.lexer;

static import binder;
import dlang_decls;
static import unknown;
import log_controls;
import manual_types;
import translate.types;
import translate.expr;

private std.d.ast.Declaration[void*] translated;
private int[std.d.ast.Declaration] placedDeclarations;
package DeferredExpression[void*] exprForDecl;

Result CHECK_FOR_DECL(Result, Input)(Input cppDecl)
{
    if (cast(void*)cppDecl in translated)
    {
        return cast(Result)translated[cast(void*)cppDecl];
        // ^ This cast failing is a huge internal programmer error
    }
    return null;
}

private LinkageAttribute translateLinkage(T)(T cppDecl, string namespace_path)
{
    LinkageAttribute result = new LinkageAttribute();
    clang.LanguageLinkage linkage = cppDecl.getLinkLanguage();
    if (cppDecl.getLinkLanguage() == manual_types.LanguageLinkage.CLanguageLinkage)
    {
        result.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        result.hasPlusPlus = false;
    }
    else if (cppDecl.getLinkLanguage() == clang.LanguageLinkage.CXXLanguageLinkage)
    {
        result.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        result.hasPlusPlus = true;
        result.identifierChain = makeIdentifierChain!"::"(namespace_path);
    }
    else if (cppDecl.getLinkLanguage() == clang.LanguageLinkage.NoLanguageLinkage)
    {
        warning(warnIfNoLinkage, "WARNING: \"", namespace_path, "::", binder.toDString(cppDecl.getSourceName()), "\" has no language linkage.  Assuming C++.");
        result.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        result.hasPlusPlus = true;
        result.identifierChain = makeIdentifierChain!"::"(namespace_path);
    }
    else {
        throw new Exception("Didn't recognize linkage");
    }
    return result;
}

private StorageClass makeStorageClass(LinkageAttribute linkage)
{
    StorageClass result = new StorageClass();
    result.linkageAttribute = linkage;
    return result;
}

private string makeDeclarationMixin(string name)
{
    import std.ascii : toUpper, toLower;
    return ("
private std.d.ast.Declaration makeDeclaration(" ~ [toUpper(name[0])] ~ name[1..$] ~ "Declaration decl)
{
    auto result = new std.d.ast.Declaration();
    result." ~ [toLower(name[0])] ~ name[1..$] ~ "Declaration = decl;
    return result;
}
").idup;
}
mixin (makeDeclarationMixin("Alias"));
mixin (makeDeclarationMixin("Enum"));
mixin (makeDeclarationMixin("Function"));
mixin (makeDeclarationMixin("Interface"));
mixin (makeDeclarationMixin("Struct"));
mixin (makeDeclarationMixin("Union"));
mixin (makeDeclarationMixin("Variable"));

private T registerDeclaration(T)(unknown.Declaration cppDecl)
{
    std.d.ast.Declaration result;
    return registerDeclaration!T(cppDecl, result);
}
private T registerDeclaration(T)(unknown.Declaration cppDecl, out std.d.ast.Declaration result)
{
    T decl = new T();
    result = makeDeclaration(decl);
    translated[cast(void*)cppDecl] = result;
    return decl;
}

private Token nameFromDecl(unknown.Declaration cppDecl)
{
    return Token(tok!"identifier", binder.toDString(cppDecl.getTargetName()), 0, 0, 0);
}

private std.d.ast.Attribute translateVisibility(T)(T cppDecl)
{
    IdType protection;
    final switch (cppDecl.getVisibility())
    {
        case unknown.Visibility.UNSET:
            throw new Exception("Unset visibility");
        case unknown.Visibility.PUBLIC:
            protection = tok!"public";
            break;
        case unknown.Visibility.PRIVATE:
            protection = tok!"private";
            break;
        case unknown.Visibility.PROTECTED:
            protection = tok!"protected";
            break;
        case unknown.Visibility.EXPORT:
            protection = tok!"export";
            break;
        case unknown.Visibility.PACKAGE:
            protection = tok!"package";
            break;
    }
    auto attrib = new Attribute();
    attrib.attribute = Token(protection, "", 0, 0, 0);
    return attrib;
}

private Attribute makeAttribute(LinkageAttribute linkage)
{
    auto result = new Attribute();
    result.linkageAttribute = linkage;
    return result;
}

class OverloadedOperatorError : Exception
{
    this()
    {
        super("Cannot translate overloaded operators.");
    }
};

private std.d.ast.IdentifierChain moduleForDeclaration(unknown.Declaration cppDecl)
{
    if (cppDecl.shouldEmit)
    {
        return destination.getModule().moduleDeclaration.moduleName;
    }
    else
    {
        return makeIdentifierChain(binder.toDString(cppDecl.getTargetModule()));
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
    DeferredSymbol[] package_internal_path;

    public:
    std.d.ast.Declaration last_result;

    public:
    this()
    {
        namespace_path = "";
        package_internal_path = [];
        last_result = null;
    }

    this(string nsp, DeferredSymbol pip)
    {
        namespace_path = nsp;
        package_internal_path = [pip];
        last_result = null;
    }

    void visit(unknown.Declaration cppDecl)
    {
        try {
            cppDecl.visit(this);
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

    std.d.ast.Declaration translateFunction(unknown.FunctionDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.Declaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        std.d.ast.Declaration outerDeclaration;
        auto d_decl = registerDeclaration!(std.d.ast.FunctionDeclaration)(cppDecl, outerDeclaration);
        // Set the linkage attributes for this function
        LinkageAttribute linkage = translateLinkage(cppDecl, namespace_path);
        outerDeclaration.attributes ~= [makeAttribute(linkage)];

        binder.binder.string target_name = cppDecl.getTargetName();
        if (target_name.size())
        {
            d_decl.name = nameFromDecl(cppDecl);
        }
        else
        {
            throw new Exception("Function declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        d_decl.returnType = translateType(cppDecl.getReturnType(), QualifierSet.init);

        d_decl.parameters = new Parameters();
        // FIXME obviously not always true
        d_decl.parameters.hasVarargs = false;

        for (auto arg_iter = cppDecl.getArgumentBegin(), arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance())
        {
            d_decl.parameters.parameters ~= [translateArgument(arg_iter.get())];
        }
        return outerDeclaration;
    }
    extern(C++) override
    void visitFunction(unknown.FunctionDeclaration cppDecl)
    {
        if (cppDecl.isOverloadedOperator())
        {
            stderr.writeln("ERROR: Cannot translate overloaded operator.");
        }
        else
        {
            translateFunction(cppDecl);
            last_result = translated[cast(void*)cppDecl];
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
                TranslatorVisitor subpackage_visitor = new TranslatorVisitor(this_namespace_path, null);
                subpackage_visitor.visit(child);

                if (subpackage_visitor.last_result && child.shouldEmit)
                {
                    placeIntoTargetModule(child, subpackage_visitor.last_result, this_namespace_path);
                }
            }
            catch (RefTypeException exc)
            {
                //child.dump();
                //stderr.writeln("ERROR: (namespace) ", exc.msg);
                //if (exc.declaration)
                //{
                //    stderr.writeln("    ref:");
                //    exc.declaration.dump();
                //}
                //stderr.writeln(exc.toString());
            }
            catch (Exception exc)
            {
                //child.dump();
                //stderr.writeln("ERROR: ", exc.msg);
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

    private void addCppLinkageAttribute(std.d.ast.Declaration declaration)
    {
        auto linkageAttribute = new LinkageAttribute();
        linkageAttribute.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        linkageAttribute.hasPlusPlus = true;
        linkageAttribute.identifierChain = makeIdentifierChain!"::"(namespace_path);
        declaration.attributes ~= [makeAttribute(linkageAttribute)];
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
            if (cast(void*)child in translated)
            {
                continue;
            }
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
                auto visitor = new SubdeclarationVisitor(namespace_path, package_internal_path[$-1]);
                unknown.Declaration decl = child;
                try {
                    visitor.visit(decl);
                }
                catch(RefTypeException e)
                {
                    e.declaration = decl;
                    throw e;
                }
                if (visitor.last_result && child.shouldEmit())
                {
                    // Already in an extern(C++, ns) context, so no need for
                    // the linkage attribute, but we needed to hold on to
                    // the namespace_path so we could generate the right
                    // qualified symbol for this thing (as applicable).
                    stripExternCpp(visitor.last_result);

                    std.d.ast.Attribute vis;
                    try {
                        vis = translateVisibility(child);
                    }
                    catch (Exception e)
                    {
                        // catch when visibility is unset.
                        // FIXME is this the right thing?
                        vis = new Attribute();
                        vis.attribute = Token(tok!"public", "", 0, 0, 0);
                    }
                    visitor.last_result.attributes ~= [vis];
                    result.structBody.declarations ~= [visitor.last_result];
                }
            }
            catch (RefTypeException exc)
            {
                //child.dump();
                //stderr.writeln("ERROR: (namespace) ", exc.msg);
                //if (exc.declaration)
                //{
                //    stderr.writeln("    ref:");
                //    exc.declaration.dump();
                //}
                //stderr.writeln(exc.toString());
            }
            catch (Exception exc)
            {
                //child.dump();
                //stderr.writeln("ERROR: ", exc.msg);
            }
        }
    }

    void translateAllBaseClasses(unknown.RecordDeclaration cppDecl, std.d.ast.InterfaceDeclaration result)
    {
        auto baseClassList = new BaseClassList();
        bool hasBaseClass = false;
        foreach (superclass; cppDecl.getSuperclassRange())
        {
            if (superclass.visibility != unknown.Visibility.PUBLIC)
            {
                throw new Exception("Don't know how to translate non-public inheritance of interfaces.");
            }
            if (superclass.isVirtual)
            {
                throw new Exception("Don't know how to translate virtual inheritance of interfaces.");
            }
            // Do the translation before checking if it's an interface because
            // the translation will force the type to pick a strategy
            std.d.ast.Type superType = translateType(superclass.base, QualifierSet.init);
            // FIXME cannot handle arbitrary replacement of superclasses
            if (superclass.base.getStrategy() != unknown.Strategy.INTERFACE
                    && superclass.base.getStrategy() != unknown.Strategy.REPLACE)
            {
                throw new Exception("Superclass of an interface (" ~ binder.toDString(cppDecl.getSourceName()) ~") is not an interface.");
            }
            std.d.ast.BaseClass base = new BaseClass();
            base.type2 = superType.type2;

            baseClassList.items ~= [base];
            hasBaseClass = true;
        }
        if (hasBaseClass)
        {
            result.baseClassList = baseClassList;
        }
    }

    std.d.ast.StructDeclaration buildStruct(unknown.RecordDeclaration cppDecl, Token name, std.d.ast.TemplateParameters template_params)
    {
        trace("Entering");
        scope(exit) trace("Exiting");

        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.StructDeclaration)(cppDecl);
        if (short_circuit !is null)
        {
            info("Short-circuiting building the struct for ", name.text, ".");
            return short_circuit;
        }

        std.d.ast.Declaration outerDeclaration;
        auto result = registerDeclaration!(std.d.ast.StructDeclaration)(cppDecl, outerDeclaration);
        result.name = name;
        result.templateParameters = template_params;

        // Set the linkage attributes for this struct
        // This only matters for methods
        // FIXME should decide on C linkage sometimes, right?
        addCppLinkageAttribute(outerDeclaration);

        result.structBody = new StructBody();

        /*
         * I need to create a field, then "alias this field",
         * FIXME But, I need to make sure the field doesn't collide with anything.
         */
        unknown.SuperclassRange all_superclasses = cppDecl.getSuperclassRange();
        if (!all_superclasses.empty())
        {
            unknown.Superclass* superclass = all_superclasses.front();
            if (superclass.visibility != unknown.Visibility.PUBLIC)
            {
                throw new Exception("Don't know how to translate non-public inheritance of structs.");
            }
            if (superclass.isVirtual)
            {
                throw new Exception("Don't know how to translate virtual inheritance of structs.");
            }
            std.d.ast.Type superType = translateType(superclass.base, QualifierSet.init);
            if (superclass.base.getStrategy() != unknown.Strategy.STRUCT)
            {
                throw new Exception("Superclass of a struct (" ~ binder.toDString(cppDecl.getSourceName()) ~ ") is not a struct.");
            }

            auto fieldDeclaration = new std.d.ast.VariableDeclaration();
            fieldDeclaration.type = superType;
            auto declarator = new std.d.ast.Declarator();
            declarator.name = Token(tok!"identifier", "_superclass", 0, 0, 0);
            fieldDeclaration.declarators ~= [declarator];
            auto fieldOuterDeclaration = new std.d.ast.Declaration();
            fieldOuterDeclaration.variableDeclaration = fieldDeclaration;
            result.structBody.declarations ~= [fieldOuterDeclaration];

            auto baseAlias = new std.d.ast.AliasThisDeclaration();
            baseAlias.identifier = Token(tok!"identifier", "_superclass", 0, 0, 0);
            auto baseDecl = new std.d.ast.Declaration();
            baseDecl.aliasThisDeclaration = baseAlias;
            result.structBody.declarations ~= [baseDecl];

            all_superclasses.popFront();
            if (!all_superclasses.empty())
            {
                throw new Exception("Cannot translate multiple inheritance of structs without multiple alias this.");
                // FIXME now, I could just put all the components in as fields and generate
                // methods that call out to those as a workaround for now.
            }
        }

        translateStructBody!(StructBodyTranslator!(VirtualBehavior.FORBIDDEN, Flag!"fields".yes))(cppDecl, result);
        info("Added ", result.structBody.declarations.length, " declarations to the body of ", name.text, '.');

        return result;
    }

    std.d.ast.InterfaceDeclaration buildInterface(unknown.RecordDeclaration cppDecl, Token name, std.d.ast.TemplateParameters template_params)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.InterfaceDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        std.d.ast.Declaration outerDeclaration;
        auto result = registerDeclaration!(std.d.ast.InterfaceDeclaration)(cppDecl, outerDeclaration);

        result.name = name;
        result.templateParameters = template_params;

        // Set the linkage attributes for this interface
        // This only matters for methods
        addCppLinkageAttribute(outerDeclaration);

        // Find the superclasses of this interface
        translateAllBaseClasses(cppDecl, result);

        result.structBody = new StructBody();
        translateStructBody!(StructBodyTranslator!(VirtualBehavior.ALLOWED, Flag!"fields".no))(cppDecl, result);

        return result;
    }

    void buildRecord(unknown.RecordDeclaration cppDecl, Token name, std.d.ast.TemplateParameters template_params)
    {
        trace("Entering");
        scope(exit) trace("Exiting");
        if (cppDecl.getDefinition() !is cppDecl)
        {
            info("Skipping this cppDecl for ", name.text, " because it is not a definition.");
            return;
        }
        determineRecordStrategy(cppDecl.getRecordType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                info("Building record using strategy STRUCT.");
                buildStruct(cppDecl, name, template_params);
                break;
            case unknown.Strategy.INTERFACE:
                info("Building record using strategy INTERFACE.");
                buildInterface(cppDecl, name, template_params);
                break;
            case unknown.Strategy.REPLACE:
                info("Skipping build because the strategy is REPLACE.");
                break;
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
        Token name = nameFromDecl(cppDecl);
        info("Translating record named ", name.text);
        IdentifierChain package_name = moduleForDeclaration(cppDecl);
        DeferredSymbol symbol = makeSymbolForTypeDecl(cppDecl, name, package_name, package_internal_path[$-1], namespace_path);
        package_internal_path ~= [symbol];
        scope(exit) package_internal_path = package_internal_path[0 .. $-1];

        buildRecord(cppDecl, name, null);
        // Records using the replacement strategy don't produce a result
        if (auto ptr = cast(void*)cppDecl in translated)
        {
            last_result = *ptr;
        }
    }

    extern(C++) override
    void visitRecordTemplate(unknown.RecordTemplateDeclaration cppDecl)
    {
        Token name = nameFromDecl(cppDecl);
        std.d.ast.TemplateParameters templateParameters = translateTemplateParameters(cppDecl);

        {
            IdentifierChain package_name = moduleForDeclaration(cppDecl);
            DeferredSymbol symbol = makeSymbolForTypeDecl(cppDecl, name, package_name, package_internal_path[$-1], namespace_path);
            package_internal_path ~= [symbol];
            scope(exit) package_internal_path = package_internal_path[0 .. $-1];

            buildRecord(cppDecl, name, templateParameters);

            // Records using the replacement strategy don't produce a result
            if (auto ptr = cast(void*)cppDecl in translated)
            {
                last_result = *ptr;
            }
        }

        // Make symbols for all of the specializations
        // This is done so that the symbols inside the specialization have
        // proper paths; the declarations themselves should not be emitted.
        foreach (unknown.SpecializedRecordDeclaration special; cppDecl.getSpecializationRange())
        {
            try {
                visitSpecializedRecord(special);
            }
            catch(Exception e)
            {
                //special.dump();
                stderr.writeln("ERROR: ", e.msg);
            }
        }

    }

    extern(C++) override
    void visitSpecializedRecord(unknown.SpecializedRecordDeclaration cppDecl)
    {
        // See note in visitRecordTemplate about why these are not emitted
        // via last_result
        auto template_inst = new std.d.ast.TemplateInstance();
        template_inst.identifier = nameFromDecl(cppDecl);
        template_inst.templateArguments = translateTemplateArguments(cppDecl);

        IdentifierChain package_name = moduleForDeclaration(cppDecl);
        DeferredSymbol symbol = makeSymbolForTypeDecl(cppDecl, template_inst, package_name, package_internal_path[$-1], namespace_path);
        package_internal_path ~= [symbol];
        scope(exit) package_internal_path = package_internal_path[0 .. $-1];

        buildRecord(cppDecl, template_inst.identifier, null);
    }

    std.d.ast.AliasDeclaration translateTypedef(unknown.TypedefDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.AliasDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        std.d.ast.Declaration outerDeclaration;
        auto result = registerDeclaration!(std.d.ast.AliasDeclaration)(cppDecl, outerDeclaration);
        auto initializer = new std.d.ast.AliasInitializer();
        addCppLinkageAttribute(outerDeclaration);
        initializer.name = nameFromDecl(cppDecl);
        initializer.type = translateType(cppDecl.getTargetType(), QualifierSet.init);
        result.initializers ~= [initializer];
        IdentifierChain package_name = moduleForDeclaration(cppDecl);
        makeSymbolForTypeDecl(cppDecl, initializer.name, package_name, package_internal_path[$-1], namespace_path);

        return result;
    }
    extern(C++) override
    void visitTypedef(unknown.TypedefDeclaration cppDecl)
    {
        translateTypedef(cppDecl);
        last_result = translated[cast(void*)cppDecl];
    }

    std.d.ast.EnumDeclaration translateEnum(unknown.EnumDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.EnumDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        auto result = registerDeclaration!(std.d.ast.EnumDeclaration)(cppDecl);
        result.enumBody = new EnumBody();

        IdentifierChain package_name = moduleForDeclaration(cppDecl);
        Token name = nameFromDecl(cppDecl);
        if (result.name.text.length > 0)
        {
            result.name = nameFromDecl(cppDecl);
            DeferredSymbol symbol = makeSymbolForTypeDecl(cppDecl, result.name, package_name, package_internal_path[$-1], namespace_path);

            package_internal_path ~= [symbol];
            scope(exit) package_internal_path = package_internal_path[0 .. $-1];
        }

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

            result.enumBody.enumMembers ~= [translateEnumConstant(constant)];
        }

        return result;
    }
    extern(C++) override void visitEnum(unknown.EnumDeclaration cppDecl)
    {
        translateEnum(cppDecl);
        last_result = translated[cast(void*)cppDecl];
    }

    std.d.ast.EnumMember translateEnumConstant(unknown.EnumConstantDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.EnumMember)(cppDecl);
        if (short_circuit !is null) return short_circuit;
        auto result = new std.d.ast.EnumMember();
        result.name = nameFromDecl(cppDecl); // TODO remove prefix
        result.assignExpression = new AssignExpression();
        PrimaryExpression constant = new PrimaryExpression();

        // FIXME, not the right types
        constant.primary = Token(tok!"longLiteral", to!string(cppDecl.getLLValue), 0, 0, 0);
        result.assignExpression = constant;

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

    std.d.ast.UnionDeclaration translateUnion(unknown.UnionDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.UnionDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        std.d.ast.Declaration outerDeclaration;
        auto result = registerDeclaration!(std.d.ast.UnionDeclaration)(cppDecl, outerDeclaration);
        if (!cppDecl.isAnonymous)
        {
            result.name = nameFromDecl(cppDecl);
        }
        result.structBody = new StructBody();

        IdentifierChain package_name = moduleForDeclaration(cppDecl);
        // If the union is anonymous, then there are not any references to it
        // in C++, so it's OK to produce a symbol that doesn't make total
        // sense, since it will never be used for that purpose.  It may be used
        // to refer to members, however, so we do need it.
        DeferredSymbol symbol = makeSymbolForTypeDecl(cppDecl, result.name, package_name, package_internal_path[$-1], namespace_path);

        package_internal_path ~= [symbol];
        scope(exit) package_internal_path = package_internal_path[0 .. $-1];

        addCppLinkageAttribute(outerDeclaration);

        if (cppDecl.getTemplateArgumentCount() > 0)
        {
            // This cast always succeeds because we know there are template
            // arguments.
            auto templateDecl = cast(unknown.UnionTemplateDeclaration)cppDecl;
            result.templateParameters = translateTemplateParameters(templateDecl);
        }

        translateStructBody!(StructBodyTranslator!(VirtualBehavior.FORBIDDEN, Flag!"fields".yes))(cppDecl, result);
        return result;
    }
    extern(C++) override void visitUnion(unknown.UnionDeclaration cppDecl)
    {
        translateUnion(cppDecl);
        last_result = translated[cast(void*)cppDecl];
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

    std.d.ast.Parameter translateArgument(unknown.ArgumentDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.Parameter)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        auto arg = new std.d.ast.Parameter();
        arg.name = nameFromDecl(cppDecl);

        unknown.Type cppType = cppDecl.getType();

        try {
            arg.type = translateType(cppType, QualifierSet.init);
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
            arg.type = translateType(targetType, QualifierSet.init).clone;
            arg.type.typeConstructors ~= [tok!"ref"];
        }

        return arg;
    }
    extern(C++) override void visitArgument(unknown.ArgumentDeclaration cppDecl)
    {
        throw new Exception("Attempting to translate an argument as if it were top level, but arguments are never top level.");
    }

    std.d.ast.VariableDeclaration translateVariable(unknown.VariableDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.VariableDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        std.d.ast.Declaration outerDeclaration;
        auto var = registerDeclaration!(std.d.ast.VariableDeclaration)(cppDecl, outerDeclaration);

        auto declarator = new Declarator();
        declarator.name = nameFromDecl(cppDecl);
        var.declarators ~= [declarator];

        makeExprForDecl(cppDecl, declarator.name, package_internal_path[$-1], namespace_path);

        addCppLinkageAttribute(outerDeclaration);

        // TODO is this the best way to see if this is a top level, global variable?
        if (package_internal_path.length == 0 || package_internal_path[$-1] is null)
        {
            auto sc = new std.d.ast.StorageClass();
            sc.token = Token(tok!"identifier", "extern", 0, 0, 0);
            var.storageClasses ~= [sc];
        }

        var.type = translateType(cppDecl.getType(), QualifierSet.init);

        return var;
    }
    extern(C++) override void visitVariable(unknown.VariableDeclaration cppDecl)
    {
        translateVariable(cppDecl);
        last_result = translated[cast(void*)cppDecl];
    }
    extern(C++) override void visitUnwrappable(unknown.UnwrappableDeclaration)
    {
        // Cannot wrap unwrappable declarations, ;)
    }

    // This should only ever be called when putting together the argument list
    // for a template, so we don't need to check for duplicates
    std.d.ast.TemplateTypeParameter translateTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration cppDecl)
    {
        auto result = new std.d.ast.TemplateTypeParameter();
        result.identifier = nameFromDecl(cppDecl);
        // TODO default values
        makeSymbolForTypeDecl(cppDecl, result.identifier, null, null, "");
        return result;
    }

    extern(C++) override void visitTemplateTypeArgument(unknown.TemplateTypeArgumentDeclaration cppDecl)
    {
        throw new Exception("Attempting to translate a template type argument not via the template itself.");
    }

    std.d.ast.TemplateValueParameter translateTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration cppDecl)
    {
        auto result = new std.d.ast.TemplateValueParameter();
        result.type = translateType(cppDecl.getType(), QualifierSet.init);
        result.identifier = nameFromDecl(cppDecl);
        // TODO default values
        makeExprForDecl(cppDecl, result.identifier, null, "");
        return result;
    }
    extern(C++) override void visitTemplateNonTypeArgument(unknown.TemplateNonTypeArgumentDeclaration cppDecl)
    {
        throw new Exception("Attempting to translate a template type argument not via the template itself.");
    }

    std.d.ast.TemplateParameter translateTemplateArgument(unknown.TemplateArgumentIterator iter)
    {
        auto result = new std.d.ast.TemplateParameter();
        final switch (iter.getKind())
        {
            case unknown.TemplateArgumentIterator.Kind.Type:
                result.templateTypeParameter = translateTemplateTypeArgument(iter.getType());
                break;
            case unknown.TemplateArgumentIterator.Kind.NonType:
                result.templateValueParameter = translateTemplateNonTypeArgument(iter.getNonType());
                break;
        }

        return result;
    }

    std.d.ast.TemplateParameters translateTemplateParameters(Declaration)(Declaration cppDecl)
    {
        auto result = new std.d.ast.TemplateParameters();
        result.templateParameterList = new std.d.ast.TemplateParameterList();

        for (unknown.TemplateArgumentIterator iter = cppDecl.getTemplateArgumentBegin(),
                end = cppDecl.getTemplateArgumentEnd();
             !iter.equals(end);
             iter.advance() )
        {
            auto current = translateTemplateArgument(iter);
            result.templateParameterList.items ~= [current];
        }

        return result;
    }

    std.d.ast.TemplateArguments translateTemplateArguments(Declaration)(Declaration cppDecl)
    {
        auto result = new std.d.ast.TemplateArguments();
        result.templateArgumentList = new std.d.ast.TemplateArgumentList();

        // TODO use the single argument syntax when appropriate
        for (unknown.TemplateArgumentInstanceIterator iter = cppDecl.getTemplateArgumentBegin(),
                end = cppDecl.getTemplateArgumentEnd();
             !iter.equals(end);
             iter.advance() )
        {
            auto current = new std.d.ast.TemplateArgument();
            final switch (iter.getKind())
            {
                case unknown.TemplateArgumentInstanceIterator.Kind.Type:
                    try {
                        current.type = translateType(iter.getType(), QualifierSet.init);
                    }
                    catch(RefTypeException e)
                    {
                        stderr.writeln("Template argument is a reference...");
                        throw e;
                    }
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
                    iter.dumpPackInfo();
                    throw new Exception("Cannot translate template Pack argument");
            }
            result.templateArgumentList.items ~= [current];
        }

        return result;
    }
}

class StructBodyTranslator
    // I want to use a Flag!"fields" instead of a bool here, but
    // that causes an ICE that I can't easily reduce.
      (VirtualBehavior vBehavior, bool fieldsAllowed)
    : TranslatorVisitor
{
    this(string nsp, DeferredSymbol pip)
    {
        super(nsp, pip);
    }

    std.d.ast.Declaration translateMethod(unknown.MethodDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.Declaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        if (cppDecl.isOverloadedOperator())
        {
            throw new OverloadedOperatorError();
        }

        std.d.ast.Declaration outerDeclaration;
        auto result = registerDeclaration!(std.d.ast.FunctionDeclaration)(cppDecl, outerDeclaration);

        if (cppDecl.isStatic())
        {
            auto attrib = new Attribute();
            attrib.attribute = Token(tok!"static", "static", 0, 0, 0);
            outerDeclaration.attributes ~= [attrib];
        }
        else
        {
            if (cppDecl.isConst())
            {
                auto attrib = new std.d.ast.MemberFunctionAttribute();
                attrib.tokenType = tok!"const";
                result.memberFunctionAttributes ~= [attrib];
            }

            if (cppDecl.isVirtual())
            {
                static if (vBehavior == VirtualBehavior.FORBIDDEN)
                {
                    throw new Exception("Methods on structs cannot be virtual!");
                    // FIXME this message may not always be correct
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
                    auto attrib = new Attribute();
                    attrib.attribute = Token(tok!"final", "final", 0, 0, 0);
                    outerDeclaration.attributes ~= [attrib];
                }
            }
        }

        if (cppDecl.getTargetName().size())
        {
            result.name = nameFromDecl(cppDecl);
        }
        else
        {
            throw new Exception("Method declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        result.returnType = translateType(cppDecl.getReturnType(), QualifierSet.init);
        if (cppDecl.getVisibility() == unknown.Visibility.UNSET)
        {
            //cppDecl.dump();
        }

        result.parameters = new Parameters();
        for (unknown.ArgumentIterator arg_iter = cppDecl.getArgumentBegin(),
                arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance() )
        {
            result.parameters.parameters ~= [translateArgument(arg_iter.get())];
        }
        return outerDeclaration;
    }

    extern(C++) override void visitMethod(unknown.MethodDeclaration cpp_method)
    {
        if (!cpp_method || !cpp_method.isWrappable())
        {
            last_result = null;
            return;
        }

        std.d.ast.Declaration method = translateMethod(cpp_method);

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
            last_result = method;
        }
        else
        {
            last_result = null;
        }
    }

    static if (fieldsAllowed)
    {
        std.d.ast.Declaration translateField(unknown.FieldDeclaration cppDecl)
        {
            auto short_circuit = CHECK_FOR_DECL!(std.d.ast.Declaration)(cppDecl);
            if (short_circuit !is null) return short_circuit;

            try {
                std.d.ast.Declaration outerDeclaration;
                // FIXME this type needs to correspond with the CHECK_FOR_DECL
                auto result = registerDeclaration!(std.d.ast.VariableDeclaration)(cppDecl, outerDeclaration);
                result.type = translateType(cppDecl.getType(), QualifierSet.init);

                auto declarator = new Declarator();
                declarator.name = nameFromDecl(cppDecl);
                result.declarators = [declarator];

                return outerDeclaration;
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
            last_result = translated[cast(void*)cppDecl];
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

private std.d.ast.Module findTargetModule(unknown.Declaration declaration)
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
    return dlang_decls.rootPackage.getOrCreateModulePath(target_module);
}

private void placeIntoTargetModule(unknown.Declaration declaration, std.d.ast.Declaration translation, string namespace_path)
{
    // FIXME sometimes this gets called multiple times on the same declaration,
    // so it will get output multiple times, which is clearly wrong
    // It happens because there are multiple declarations of the same type
    // (e.g. forward and normal), that have the same translation
    if (translation)
    {
        if (translation in placedDeclarations)
        {
            return;
        }

        destination.addDeclaration(translation, namespace_path);
        placedDeclarations[translation] = 1;
    }
}

dlang_decls.ModuleWithNamespaces destination;

std.d.ast.Module populateDAST(string output_module_name)
{
    // May cause problems because root package won't check for empty path.
    size_t array_len = 0;
    unknown.Declaration* freeDeclarations = null;
    unknown.arrayOfFreeDeclarations(&array_len, &freeDeclarations);

    destination = new dlang_decls.ModuleWithNamespaces(output_module_name);

    for (size_t i = 0; i < array_len; ++i)
    {
        unknown.Declaration declaration = freeDeclarations[i];
        if (!declaration.isWrappable())// || !declaration.shouldEmit())
        {
            continue;
        }

        std.d.ast.IdentifierChain moduleName = null;
        if (declaration.shouldEmit())
        {
            std.d.ast.Module mod = findTargetModule(declaration);
            moduleName = mod.moduleDeclaration.moduleName;
        }

        auto visitor = new TranslatorVisitor("", null);
        try {
            std.d.ast.Declaration translation;
            if (cast(void*)declaration !in translated)
            {
                visitor.visit(declaration);
                translation = visitor.last_result;
            }
            else
            {
                translation = translated[cast(void*)declaration];
            }

            // some items, such as namespaces, don't need to be placed into a module.
            // visiting them just translates their children and puts them in modules
            if (translation && declaration.shouldEmit)
            {
                placeIntoTargetModule(declaration, translation, "");
            }
        }
        catch(RefTypeException exc)
        {
            //declaration.dump();
            //stderr.writeln("ERROR: ", exc.msg);
            //stderr.writeln(exc.toString());
        }
        catch (Exception exc)
        {
            //declaration.dump();
            //stderr.writeln("ERROR: ", exc.msg);
        }

    }

    if (unresolvedSymbols.length > 0)
    {
        // We're going to remove types from unresolvedTypes as we
        // resolve them, so take a copy before iterating
        auto local_copy = unresolvedSymbols.dup;
        foreach (symbol, decl; local_copy)
        {
            resolveSymbol(symbol, decl);
        }
        if (unresolvedSymbols.length > 0)
        {
            throw new Exception("Not all types could be resolved.");
        }
    }

    foreach (DeferredTemplateInstantiation temp; deferredTemplates.values())
    {
        temp.resolve();
    }

    return destination.getModule();
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

class NoDefinitionException : Exception
{
    this(unknown.Declaration decl)
    {
      super(to!string(decl.getSourceName().c_str()) ~ " has no definition, so I cannot determine a translation strategy.");
    }
}

package void resolveSymbol(DeferredSymbol symbol, unknown.Declaration cppDecl)
{
    if (cppDecl !is null && cppDecl.getType() !is null)
    {
        determineStrategy(cppDecl.getType());
    }
    symbol.resolve();
    unresolvedSymbols.remove(symbol);
}

string makeString(IdentifierChain chain)
{
    auto dest = appender!string();
    format(delegate(const char[] t) { dest.put(t); }, chain);
    return dest.data.idup;
}
string makeString(const std.d.ast.Symbol sym)
{
    auto dest = appender!string();
    format(delegate(const char[] t) { dest.put(t); }, sym);
    return dest.data.idup;
}

// Only call this on declarations that DO NOT declare a type!
// TODO Type vs. non-type should be reflected by the inheritance hierarchy of
// the unknown.Declaration types.
package DeferredExpression makeExprForDecl
    (unknown.Declaration cppDecl, IdentifierOrTemplateInstance targetName, DeferredSymbol internal_path, string namespace_path)
{
    import std.array : join;
    import std.algorithm : map;

    DeferredExpression expression;
    if (auto e_ptr = (cast(void*)cppDecl) in exprForDecl)
    {
        expression = *e_ptr;
    }
    else
    {
        expression = new DeferredExpression(null);
        exprForDecl[cast(void*)cppDecl] = expression;
    }
    DeferredSymbolConcatenation symbol;

    if (expression.symbol is null)
    {
        symbol = new DeferredSymbolConcatenation();
        expression.symbol = symbol;
    }
    else
    {
        symbol = expression.symbol;
    }

    unresolvedSymbols[symbol] = cppDecl;

    if (symbol.length == 0)
    {
        if (internal_path is null)
            // Internal path is now a fully qualifed deferred symbol, so
            // it obseletes the package name.
            // FIXME the name "internal_path", since it's not internal anymore
            // Package can be null for things like template arguments
        {
            // FIXME get rid of this case?
        }
        if (internal_path !is null) // internal_path is null at the top level inside a module
        {
            symbol.append(internal_path);
        }
        auto namespace_chain = makeIdentifierOrTemplateChain!"::"(namespace_path);
        if (namespace_chain.identifiersOrTemplateInstances.length > 0)
            // Things like template arguments aren't really in a namespace
        {
            symbol.append(namespace_chain);
        }
        symbol.append(targetName);
    }

    assert (symbol.length > 0);
    return expression;
}

package DeferredExpression makeExprForDecl
    (SourceDeclaration)
    (SourceDeclaration cppDecl, Token targetName, DeferredSymbol internal_path, string namespace_path)
{
    auto inst = new std.d.ast.IdentifierOrTemplateInstance();
    inst.identifier = targetName;
    return makeExprForDecl(cppDecl, inst, internal_path, namespace_path);
}
package DeferredExpression makeExprForDecl
    (SourceDeclaration)
    (SourceDeclaration cppDecl, TemplateInstance targetName, DeferredSymbol internal_path, string namespace_path)
{
    auto inst = new std.d.ast.IdentifierOrTemplateInstance();
    inst.templateInstance = targetName;
    return makeExprForDecl(cppDecl, inst, internal_path, namespace_path);
}
