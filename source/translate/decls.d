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

import std.d.ast;
import std.d.formatter : format;
import std.d.lexer;

static import binder;
import dlang_decls;
static import unknown;
import manual_types;
import translate.types;

private std.d.ast.Declaration[void*] translated;
private std.d.ast.Module[std.d.ast.Declaration] placedDeclarations;

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
        result.identifierChain = makeIdentifierChain(namespace_path);
    }
    else if (cppDecl.getLinkLanguage() == clang.LanguageLinkage.NoLanguageLinkage)
    {
        cppDecl.dump();
        stderr.writeln("WARNING: symbol has no language linkage.  Assuming C++.");
        result.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        result.hasPlusPlus = true;
        result.identifierChain = makeIdentifierChain(namespace_path);
    }
    else {
        stderr.writeln("Didn't recognize linkage");
        assert(0);
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

private class TranslatorVisitor : unknown.DeclarationVisitor
{
    IdentifierChain parent_package_name;
    string namespace_path;
    DeferredSymbol[] package_internal_path;

    public:
    std.d.ast.Declaration last_result;

    public:
    this()
    {
        parent_package_name = new IdentifierChain();
        namespace_path = "";
        package_internal_path = [];
        last_result = null;
    }

    this(IdentifierChain parent, string nsp, DeferredSymbol pip)
    {
        parent_package_name = parent;
        namespace_path = nsp;
        package_internal_path = [pip];
        last_result = null;
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

    dlang_decls.Module translateNamespace(unknown.NamespaceDeclaration cppDecl)
    {
        import std.algorithm : join, map;
        // TODO I probably shouldn't even be doing this,
        // just looping over all of the items in the namespace and setting the
        // target_module attribute (if it's not already set),
        // and then visiting those nodes.  Then the modules / packages get
        // created when something goes in them.
        dlang_decls.Module mod;
        if (cast(void*)cppDecl in translated)
        {
            std.d.ast.Declaration search = translated[cast(void*)cppDecl];
            // This cast failing means that we previously translated this
            // namespace as something other than a module, which is a really
            // bad logic error.
            mod = cast(dlang_decls.Module)(search);
            if (!mod)
            {
                throw new Error("Translated a namespace to something other than a module.");
            }
        }
        else
        {
            string name = binder.toDString(cppDecl.getTargetName());
            mod = dlang_decls.rootPackage.getOrCreateModulePath(name);
        }

        IdentifierChain this_package_name = mod.moduleDeclaration.moduleName;
        string package_name_string = this_package_name.identifiers.map!(t => t.text).join(".");

        for (unknown.DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             !children_iter.equals(children_end);
             children_iter.advance())
        {
            if (!children_iter.get().isTargetModuleSet())
            {
                // FIXME someday, use an IdentifierChain here
                children_iter.get().setTargetModule(binder.toBinderString(package_name_string));
            }
        }

        // This is the translated name, but really I want the C++ name
        string this_namespace_path = namespace_path ~ "::" ~ this_package_name.identifiers[$-1].text;
        // visit and translate all of the children
        for (unknown.DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             !children_iter.equals(children_end);
             children_iter.advance())
        {
            try {
                TranslatorVisitor subpackage_visitor = new TranslatorVisitor(this_package_name, this_namespace_path, null);
                children_iter.get().visit(subpackage_visitor);

                placeIntoTargetModule(children_iter.get(), subpackage_visitor.last_result);
            }
            catch (Exception exc)
            {
                children_iter.get().dump();
                stderr.writeln("ERROR: ", exc.msg);
            }
        }

        return mod;
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
        linkageAttribute.identifierChain = makeIdentifierChain(namespace_path);
        declaration.attributes ~= [makeAttribute(linkageAttribute)];
    }

    private void translateAllFields(unknown.RecordDeclaration cppDecl, std.d.ast.StructDeclaration result)
    {
        for (unknown.FieldIterator iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             !iter.equals(finish);
             iter.advance())
        {
            Declaration field = translateField(iter.get());
            result.structBody.declarations ~= [field];
        }
    }

    private void translateAllMethods
        (VirtualBehavior virtualPolicy, Record)
        (unknown.RecordDeclaration cppDecl, Record result)
    {
        for (unknown.MethodIterator iter = cppDecl.getMethodBegin(),
                  finish = cppDecl.getMethodEnd();
             !iter.equals(finish);
             iter.advance())
        {
            // sometimes, e.g. for implicit destructors, the lookup from clang
            // type to my types fails.  So we should skip those.
            unknown.MethodDeclaration cpp_method = iter.get();
            if (!cpp_method || !cpp_method.getShouldBind())
                continue;

            try {
                std.d.ast.Declaration method = translateMethod!virtualPolicy(iter.get());

                bool shouldInsert = true;
                static if (virtualPolicy != VirtualBehavior.FORBIDDEN)
                {
                    bool no_bound_overrides = true;
                    for (unknown.OverriddenMethodIterator override_iter = cpp_method.getOverriddenBegin(),
                            override_finish = cpp_method.getOverriddenEnd();
                         !override_iter.equals(override_finish) && no_bound_overrides;
                         override_iter.advance() )
                    {
                        unknown.MethodDeclaration superMethod = override_iter.get();
                        if (superMethod.getShouldBind())
                        {
                            no_bound_overrides = false;
                        }
                    }
                    shouldInsert = no_bound_overrides;
                }

                if (shouldInsert)
                {
                    result.structBody.declarations ~= [method];
                }
            }
            catch (OverloadedOperatorError exc)
            {
                stderr.writeln("ERROR: ", exc.msg);
                continue;
            }
            catch (Exception exc)
            {
                stderr.writeln("ERROR: Cannot translate method ", binder.toDString(cppDecl.getSourceName()), "::", binder.toDString(cpp_method.getSourceName()), ", skipping it");
                stderr.writeln("\t", exc.msg);
                continue;
            }
        }
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

            if (inner.getChildBegin().equals(inner.getChildEnd()))
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
        (SubdeclarationVisitor, TargetDeclaration)
        (unknown.RecordDeclaration cppDecl, TargetDeclaration result)
    {
        for (unknown.DeclarationIterator iter = cppDecl.getChildBegin(),
                finish = cppDecl.getChildEnd();
            !iter.equals(finish);
            iter.advance())
        {
            if (cast(void*)iter.get() in translated)
            {
                continue;
            }
            try {
                // FIXME the check for whether or not to bind shouldn't be made
                // everywhere; there should be a good, common place for it
                if (isEmptyDuplicateStructThingy(cppDecl, iter.get()) || !iter.get().getShouldBind())
                {
                    continue;
                }
                auto visitor = new SubdeclarationVisitor(parent_package_name, namespace_path, package_internal_path[$-1]);
                unknown.Declaration decl = iter.get();
                decl.visit(visitor);
                if (visitor.last_result)
                {
                    result.structBody.declarations ~= [visitor.last_result];
                }
            }
            catch (Exception e)
            {
                iter.get().dump();
                stderr.writeln("ERROR: ", e.msg);
            }
        }
    }

    void translateAllBaseClasses(unknown.RecordDeclaration cppDecl, std.d.ast.InterfaceDeclaration result)
    {
        auto baseClassList = new BaseClassList();
        bool hasBaseClass = false;
        for (unknown.SuperclassIterator iter = cppDecl.getSuperclassBegin(),
                finish = cppDecl.getSuperclassEnd();
             !iter.equals(finish);
             iter.advance())
        {
            unknown.Superclass* superclass = iter.get();
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
                throw new Exception("Superclass (" ~ binder.toDString(cppDecl.getSourceName()) ~") of an interface is not an interface.");
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
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.StructDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        std.d.ast.Declaration outerDeclaration;
        auto result = registerDeclaration!(std.d.ast.StructDeclaration)(cppDecl, outerDeclaration);
        result.name = name;
        result.templateParameters = template_params;

        // Set the linkage attributes for this struct
        // This only matters for methods
        // FIXME should decide on C linkage sometimes, right?
        addCppLinkageAttribute(outerDeclaration);

        result.structBody = new StructBody();

        translateAllFields(cppDecl, result);
        translateAllMethods!(VirtualBehavior.FORBIDDEN)(cppDecl, result);
        translateStructBody!TranslatorVisitor(cppDecl, result);

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
        translateAllMethods!(VirtualBehavior.ALLOWED)(cppDecl, result);
        translateStructBody!InterfaceBodyTranslator(cppDecl, result);

        return result;
    }

    void buildRecord(unknown.RecordDeclaration cppDecl, Token name, std.d.ast.TemplateParameters template_params)
    {
        if (cppDecl.getDefinition() !is cppDecl && cppDecl.getDefinition() !is null)
            return;
        determineRecordStrategy(cppDecl.getRecordType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                buildStruct(cppDecl, name, template_params);
                break;
            case unknown.Strategy.INTERFACE:
                buildInterface(cppDecl, name, template_params);
                break;
            case unknown.Strategy.REPLACE:
                break;
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate records using strategies other than REPLACE, STRUCT, and INTERFACE yet.");
        }

    }
    extern(C++) override
    void visitRecord(unknown.RecordDeclaration cppDecl)
    {
        Token name = nameFromDecl(cppDecl);
        DeferredSymbol symbol = makeSymbolForDecl(cppDecl, name, parent_package_name, package_internal_path[$-1], namespace_path);
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
            DeferredSymbol symbol = makeSymbolForDecl(cppDecl, name, parent_package_name, package_internal_path[$-1], namespace_path);
            package_internal_path ~= [symbol];
            scope(exit) package_internal_path = package_internal_path[0 .. $-1];

            buildRecord(cppDecl, name, templateParameters);
            last_result = translated[cast(void*)cppDecl];
        }

        // Make symbols for all of the specializations
        // This is done so that the symbols inside the specialization have
        // proper paths; the declarations themselves shoudl not be emitted.
        for (auto iter = cppDecl.getSpecializationBegin(), end = cppDecl.getSpecializationEnd();
             !iter.equals(end);
             iter.advance())
        {
            unknown.SpecializedRecordDeclaration special = iter.get();
            visitSpecializedRecord(special);
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

        DeferredSymbol symbol = makeSymbolForDecl(cppDecl, template_inst, parent_package_name, package_internal_path[$-1], namespace_path);
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
        makeSymbolForDecl(cppDecl, initializer.name, parent_package_name, package_internal_path[$-1], namespace_path);

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

        result.name = nameFromDecl(cppDecl);
        DeferredSymbol symbol = makeSymbolForDecl(cppDecl, result.name, parent_package_name, package_internal_path[$-1], namespace_path);

        package_internal_path ~= [symbol];
        scope(exit) package_internal_path = package_internal_path[0 .. $-1];

        unknown.Type cppType = cppDecl.getMemberType();
        result.type = translateType(cppType, QualifierSet.init);

        // TODO bring this block back in
        //try {
        //    result.visibility = translateVisibility(cppDecl.getVisibility());
        //}
        //catch (Exception e)  // FIXME also catches thing that were logic error
        //{
        //    // catch when visibility is unset.
        //    // FIXME is this the right thing?
        //    result.visibility = dlang_decls.Visibility.PUBLIC;
        //}

        // visit and translate all of the constants
        for (unknown.DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             !children_iter.equals(children_end);
             children_iter.advance() )
        {
            unknown.EnumConstantDeclaration constant = cast(unknown.EnumConstantDeclaration)children_iter.get();
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
        result.assignExpression.assignExpression = constant;

        return result;
    }
    extern(C++) override void visitEnumConstant(unknown.EnumConstantDeclaration)
    {
        // Getting here means that there is an enum constant declaration
        // outside of an enum declaration, since visitEnum calls
        // translateEnumConstant directly.
        throw new Error("Attempted to translate an enum constant directly, instead of via an enum.");
    }

    std.d.ast.Declaration translateField(unknown.FieldDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.Declaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        std.d.ast.Declaration outerDeclaration;
        // FIXME this type needs to correspond with the CHECK_FOR_DECL
        auto result = registerDeclaration!(std.d.ast.VariableDeclaration)(cppDecl, outerDeclaration);
        result.type = translateType(cppDecl.getType(), QualifierSet.init);

        auto declarator = new Declarator();
        declarator.name = nameFromDecl(cppDecl);
        result.declarators = [declarator];

        outerDeclaration.attributes ~= [translateVisibility(cppDecl)];

        return outerDeclaration;
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
        result.name = nameFromDecl(cppDecl);
        result.structBody = new StructBody();

        DeferredSymbol symbol = makeSymbolForDecl(cppDecl, result.name, parent_package_name, package_internal_path[$-1], namespace_path);

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

        for (unknown.FieldIterator iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             !iter.equals(finish);
             iter.advance() )
        {
            std.d.ast.Declaration field = translateField(iter.get());
            result.structBody.declarations ~= [field];
        }

        // TODO static methods and other things?
        return result;
    }
    extern(C++) override void visitUnion(unknown.UnionDeclaration cppDecl)
    {
        translateUnion(cppDecl);
        last_result = translated[cast(void*)cppDecl];
    }

    enum VirtualBehavior {
        ALLOWED,
        REQUIRED,
        FORBIDDEN,
    }
    std.d.ast.Declaration translateMethod(VirtualBehavior vBehavior)(unknown.MethodDeclaration cppDecl)
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
            cppDecl.dump();
        }
        outerDeclaration.attributes ~= [translateVisibility(cppDecl)];

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

    extern(C++) override void visitMethod(unknown.MethodDeclaration)
    {
        // Getting here means that there is a method declaration
        // outside of a record declaration, since the struct / interface building
        // functions call translateMethod directly.
        throw new Exception("Attempting to translate a method as if it were top level, but methods are never top level.");
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
        auto var = registerDeclaration!(std.d.ast.VariableDeclaration)(cppDecl);

        var.storageClasses ~= [makeStorageClass(translateLinkage(cppDecl, namespace_path))];

        // TODO is this the best way to see if this is a top level, global variable?
        if (package_internal_path.length == 0 || package_internal_path[$-1] is null)
        {
            auto sc = new std.d.ast.StorageClass();
            sc.token = Token(tok!"identifier", "extern", 0, 0, 0);
            var.storageClasses ~= [sc];
        }

        auto declarator = new Declarator();
        declarator.name = nameFromDecl(cppDecl);
        var.declarators ~= [declarator];
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
        makeSymbolForDecl(cppDecl, result.identifier, null, null, "");
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
        makeSymbolForDecl(cppDecl, result.identifier, null, null, "");
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
            // TODO only translating types for now
            auto current = new std.d.ast.TemplateArgument();
            current.type = translateType(iter.get(), QualifierSet.init);
            result.templateArgumentList.items ~= [current];
        }

        return result;
    }
}

// FIXME this is a kludge to deal with the fact that interfaces cannot have
// fields.  I've thought about adding a subclass of DeclarationVisitor for
// each different kind of context and mixing in the methods that it supports.
// But for now, the cost of moving to that is too high.
class InterfaceBodyTranslator : TranslatorVisitor
{
    this(IdentifierChain parent, string nsp, DeferredSymbol pip)
    {
        super(parent, nsp, pip);
    }

    extern(C++) override void visitField(unknown.FieldDeclaration)
    {
        last_result = null;
    }

    extern(C++) override void visitMethod(unknown.MethodDeclaration cppDecl)
    {
        // We need to skip methods that won't be wrapped, because otherwise
        // the superclass will complain that we are trying to emit a method
        // from an invalid context.  Not that visitMethod is not called for
        // methods that have already been translated.
        if (cppDecl.isOverloadedOperator())
        {
            return;
        }
        else
        {
            super.visitMethod(cppDecl);
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
private void placeIntoTargetModule(unknown.Declaration declaration, std.d.ast.Declaration translation)
{
    // FIXME sometimes this gets called multiple times on the same declaration,
    // so it will get output multiple times, which is clearly wrong
    // It happens because there are multiple declarations of the same type
    // (e.g. forward and normal), that have the same translation
    if (translation in placedDeclarations)
    {
        return;
    }
    if (translation)
    {
        std.d.ast.Module mod = findTargetModule(declaration);
        mod.declarations ~= [translation];
        placedDeclarations[translation] = mod;
    }
}

void populateDAST()
{
    // May cause problems because root package won't check for empty path.
    size_t array_len = 0;
    unknown.Declaration* freeDeclarations = null;
    unknown.arrayOfFreeDeclarations(&array_len, &freeDeclarations);

    for (size_t i = 0; i < array_len; ++i)
    {
        unknown.Declaration declaration = freeDeclarations[i];
        if (!declaration.getShouldBind())
        {
            continue;
        }

        std.d.ast.Module mod = findTargetModule(declaration);
        auto visitor = new TranslatorVisitor(mod.moduleDeclaration.moduleName, "", null);
        try {
            std.d.ast.Declaration translation;
            if (cast(void*)declaration !in translated)
            {
                declaration.visit(visitor);
                translation = visitor.last_result;
            }
            else
            {
                translation = translated[cast(void*)declaration];
            }

            // some items, such as namespaces, don't need to be placed into a module
            // visiting them just translates their children and puts them in modules
            if (translation)
            {
                placeIntoTargetModule(declaration, translation);
            }
        }
        catch (Exception exc)
        {
            declaration.dump();
            stderr.writeln("ERROR: ", exc.msg);
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
            symbol.resolve();
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

    foreach (path, mod; rootPackage.children)
    {
        computeImports(mod);
    }
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
    assert(cpp_decl !is null);

    if (!cpp_decl.isCXXRecord())
    {
        cppType.setStrategy(unknown.Strategy.STRUCT);
    }
    else
    {
        if (!cpp_decl.hasDefinition())
        {
            throw new NoDefinitionException(cpp_decl);
        }

        if(cpp_decl.isDynamicClass())
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

private class SymbolFinder : std.d.ast.ASTVisitor
{
    public int[string] modules;
    // Since I'm overriding a particular overload of visit, alias them all in
    alias visit = ASTVisitor.visit;

    override
    void visit(const std.d.ast.Symbol sym)
    {
        if (auto pmod = sym in symbolModules)
        {
            string mod = *pmod;
            if (mod == "." || mod == "")
            {
                // indicates global scope, no import necessary
                return;
            }
            int* counter = (mod in modules);
            if (counter is null)
            {
                modules[mod] = 0;
            }
            else
            {
                (*counter) += 1;
            }
        }
        else if ((sym in deferredTemplates) is null)
        {
            string symbol_name = makeString(sym);
            // FIXME this is always a false positive on template arguments.
            stderr.writeln("WARNING: Could not find the module containing \"", symbol_name, "\", there may be undefined symbols in the generated code.");
        }
    }
}

void computeImports(Module mod)
{
    auto sf = new SymbolFinder();
    sf.visit(mod);
    Declaration imports = new Declaration();
    imports.importDeclaration = new ImportDeclaration();

    // Don't need to import ourselves
    string my_name = makeString(mod.moduleDeclaration.moduleName);
    if (my_name in sf.modules)
    {
        sf.modules.remove(my_name);
    }

    foreach (name, count; sf.modules)
    {
        SingleImport currentImport = new SingleImport();
        currentImport.identifierChain = makeIdentifierChain(name);
        imports.importDeclaration.singleImports ~= [currentImport];
    }

    if (sf.modules.length > 0)
    {
        mod.declarations = [imports] ~ mod.declarations;
    }
}
