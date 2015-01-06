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

import core.exception : RangeError;
import std.array;
import std.conv : to;
import std.stdio : stdout, stderr;

import std.d.ast;
import std.d.lexer;

static import binder;
import dlang_decls;
static import unknown;
import manual_types;
import translate.types : translated_types, translateType;

private std.d.ast.Declaration[void*] translated;
private std.d.ast.Module[std.d.ast.Declaration] placedDeclarations;
private std.d.ast.Declaration[std.d.ast.Type] unresolvedTypes;

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
    Declaration result = new Declaration();
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
    T decl = new T();
    Declaration result = makeDeclaration(decl);
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

private std.d.ast.Type declToType(Declaration)(Declaration decl)
{
    // TODO
    return null;
}

class OverloadedOperatorError : Exception
{
    this()
    {
        super("Cannot translate overloaded operators.");
    }
};

// Would kind of like a WhiteHole for these
private class TranslatorVisitor : unknown.DeclarationVisitor
{
    string parent_package_name;
    string namespace_path;
    public:
    std.d.ast.Declaration last_result;

    public:
    this(string parent, string nsp)
    {
        namespace_path = nsp;
        last_result = null;
    }

    std.d.ast.FunctionDeclaration translateFunction(unknown.FunctionDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.FunctionDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        auto d_decl = registerDeclaration!(std.d.ast.FunctionDeclaration)(cppDecl);
        // Set the linkage attributes for this function
        LinkageAttribute linkage = translateLinkage(cppDecl, namespace_path);
        d_decl.attributes = [makeAttribute(linkage)];

        binder.binder.string target_name = cppDecl.getTargetName();
        if (target_name.size())
        {
            d_decl.name = nameFromDecl(cppDecl);
        }
        else
        {
            throw new Exception("Function declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        d_decl.returnType = translateType(cppDecl.getReturnType());

        // FIXME obviously not always true
        d_decl.parameters = new Parameters();
        d_decl.parameters.hasVarargs = false;

        for (auto arg_iter = cppDecl.getArgumentBegin(), arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance())
        {
            // FIXME check these types
            d_decl.parameters.parameters ~= [translateArgument(arg_iter.get())];
        }
        return d_decl;
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

        //string this_package_name = parent_package_name ~ "." ~ mod.getName();
        string this_package_name = mod.moduleDeclaration.moduleName.identifiers
            .map!( t => t.text )
            .join(".");

        for (unknown.DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             !children_iter.equals(children_end);
             children_iter.advance())
        {
            if (!children_iter.get().isTargetModuleSet())
            {
                // FIXME construct a binder.string
                children_iter.get().setTargetModule(binder.toBinderString(this_package_name));
            }
        }

        // This is the translated name, but really I want the C++ name
        string this_namespace_path = namespace_path ~ "::" ~ mod.moduleDeclaration.moduleName.identifiers[$-1].text;
        // visit and translate all of the children
        for (unknown.DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             !children_iter.equals(children_end);
             children_iter.advance())
        {
            try {
                TranslatorVisitor subpackage_visitor = new TranslatorVisitor(this_package_name, this_namespace_path);
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

    std.d.ast.StructDeclaration buildStruct(unknown.RecordDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.StructDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        auto result = registerDeclaration!(std.d.ast.StructDeclaration)(cppDecl);
        translated_types[cppDecl.getType()] = declToType(result);
        result.name = nameFromDecl(cppDecl);

        // Set the linkage attributes for this struct
        // This only matters for methods
        // FIXME should decide on C linkage sometimes, right?
        result.linkageAttribute = new LinkageAttribute();
        result.linkageAttribute.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        result.linkageAttribute.hasPlusPlus = true;
        result.linkageAttribute.identifierChain = makeIdentifierChain(namespace_path);

        result.structBody = new StructBody();

        for (unknown.FieldIterator iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             !iter.equals(finish);
             iter.advance())
        {
            VariableDeclaration field = translateField(iter.get());
            result.structBody.declarations ~= [makeDeclaration(field)];
        }

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
            std.d.ast.FunctionDeclaration method;
            try {
                method = translateMethod(iter.get(), VirtualBehavior.FORBIDDEN);
            }
            catch (Exception exc)
            {
                stderr.writeln("ERROR: Cannot translate method ", cppDecl.getSourceName(), "::", cpp_method.getSourceName(), ", skipping it");
                stderr.writeln("\t", exc.msg);
                continue;
            }
            result.structBody.declarations ~= [makeDeclaration(method)];
        }

        // TODO static methods and other things
        for (unknown.DeclarationIterator iter = cppDecl.getChildBegin(),
                finish = cppDecl.getChildEnd();
            !iter.equals(finish);
            iter.advance())
        {
            // FIXME this cast doesn't work in D (doesn't have the right RTTI)
            // So I'm abandoning this special case for now
            /*if (unknown.EnumDeclaration enumDecl = cast(unknown.EnumDeclaration)(iter.get()) )
            {
                result.insert(translateEnum(enumDecl));
            }*/
        }
        return result;
    }

    std.d.ast.InterfaceDeclaration buildInterface(unknown.RecordDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.InterfaceDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        auto result = registerDeclaration!(std.d.ast.InterfaceDeclaration)(cppDecl);
        result.structBody = new StructBody();
        // TODO It looks like I elided this check in buildStruct,
        // Can I elide it here also, or does it need to go back in above?
        // Eliding it because I need to rethink this for libdparse
        //if (cppDecl.getType() in translated_types)
        //{
        //    return translated_types[cppDecl.getType()].interfaceDeclaration;
        //}
        translated_types[cppDecl.getType()] = declToType(result);
        result.name = nameFromDecl(cppDecl);

        // Set the linkage attributes for this interface
        // This only matters for methods
        result.linkageAttribute = new LinkageAttribute();
        result.linkageAttribute.identifier = Token(tok!"identifier", "C", 0, 0, 0);
        result.linkageAttribute.hasPlusPlus = true;
        result.linkageAttribute.identifierChain = makeIdentifierChain(namespace_path);

        // Find the superclasses of this interface
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
            std.d.ast.Type superType = translateType(superclass.base);
            // FIXME cannot handle arbirary replacement of superclasses
            // Also, this cast will always face because interface declarations aren't types
            auto superInterface = cast(std.d.ast.InterfaceDeclaration)superType;
            if (!superInterface)
            {
                throw new Exception("Superclass of an interface is not an interface.");
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

        for( unknown.MethodIterator iter = cppDecl.getMethodBegin(),
                  finish = cppDecl.getMethodEnd();
             !iter.equals(finish);
             iter.advance() )
        {
            // sometimes, e.g. for implicit destructors, the lookup from clang
            // type to my types fails.  So we should skip those.
            unknown.MethodDeclaration cpp_method = iter.get();
            if (cpp_method is null || !cpp_method.getShouldBind())
                continue;
            try {
                // FIXME triple dereference? really?
                std.d.ast.FunctionDeclaration method = translateMethod(iter.get(), VirtualBehavior.REQUIRED);
                result.structBody.declarations ~= [makeDeclaration(method)];
            }
            catch (OverloadedOperatorError e)
            {
                if (cpp_method.isVirtual())
                {
                    throw e;
                }
                stderr.writeln("ERROR: ", e.msg);
            }
        }

        // TODO static methods and other things
        return result;
    }

    extern(C++) override
    void visitRecord(unknown.RecordDeclaration cppDecl)
    {
        determineRecordStrategy(cppDecl.getType());
        switch (cppDecl.getType().getStrategy())
        {
            case unknown.Strategy.STRUCT:
                buildStruct(cppDecl);
                last_result = translated[cast(void*)cppDecl];
                break;
            case unknown.Strategy.INTERFACE:
                buildInterface(cppDecl);
                last_result = translated[cast(void*)cppDecl];
                break;
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate records using strategies other than STRUCT and INTERFACE yet.");
        }
    }

    // FIXME I don't understand libdparse aliases
    std.d.ast.AliasDeclaration translateTypedef(unknown.TypedefDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.AliasDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        auto result = registerDeclaration!(std.d.ast.AliasDeclaration)(cppDecl);
        translated_types[cppDecl.getType()] = declToType(result);
        result.identifierList = new IdentifierList();
        result.identifierList.identifiers = [nameFromDecl(cppDecl)];
        result.type = translateType(cppDecl.getTargetType());

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
        translated_types[cppDecl.getType()] = declToType(result);
        result.enumBody = new EnumBody();

        unknown.Type * cppType = cppDecl.getType();
        result.type = translateType(cppType);
        result.name = nameFromDecl(cppDecl);
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
        result.type = translateType(cppDecl.getType());
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

    std.d.ast.VariableDeclaration translateField(unknown.FieldDeclaration cppDecl)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.VariableDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;
        auto result = registerDeclaration!(std.d.ast.VariableDeclaration)(cppDecl);
        result.type = translateType(cppDecl.getType());

        auto declarator = new Declarator();
        declarator.name = nameFromDecl(cppDecl);
        result.declarators = [declarator];

        result.attributes ~= [translateVisibility(cppDecl)];

        return result;
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

        auto result = registerDeclaration!(std.d.ast.UnionDeclaration)(cppDecl);
        translated_types[cppDecl.getType()] = declToType(result);
        result.name = nameFromDecl(cppDecl);
        result.structBody = new StructBody();

        for (unknown.FieldIterator iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             !iter.equals(finish);
             iter.advance() )
        {
            std.d.ast.VariableDeclaration field = translateField(iter.get());
            result.structBody.declarations ~= [makeDeclaration(field)];
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
    std.d.ast.FunctionDeclaration translateMethod(unknown.MethodDeclaration cppDecl, VirtualBehavior vBehavior)
    {
        auto short_circuit = CHECK_FOR_DECL!(std.d.ast.FunctionDeclaration)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        if (cppDecl.isOverloadedOperator())
        {
            throw new OverloadedOperatorError();
        }

        auto result = new std.d.ast.FunctionDeclaration();

        if (cppDecl.isStatic())
        {
            auto attrib = new Attribute();
            attrib.attribute = Token(tok!"static", "static", 0, 0, 0);
            result.attributes ~= [attrib];
        }
        else if (cppDecl.isVirtual())
        {
            if (vBehavior == VirtualBehavior.FORBIDDEN)
            {
                throw new Exception("Methods on structs cannot be virtual!");
                // FIXME this message may not always be correct
            }
            // virtual is implied by context i.e. must be in class, interface,
            // then it's by default, so no attribute here
        }
        else {
            if (vBehavior == VirtualBehavior.REQUIRED)
            {
                // FIXME this message may not always be correct
                throw new Exception("Methods on interfaces must be virtual!");
            }
            else
            {
                auto attrib = new Attribute();
                attrib.attribute = Token(tok!"final", "final", 0, 0, 0);
                result.attributes ~= [attrib];
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

        result.returnType = translateType(cppDecl.getReturnType());
        if (cppDecl.getVisibility() == unknown.Visibility.UNSET)
            cppDecl.dump();
        result.attributes ~= [translateVisibility(cppDecl)];

        result.parameters = new Parameters();
        for (unknown.ArgumentIterator arg_iter = cppDecl.getArgumentBegin(),
                arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance() )
        {
            result.parameters.parameters ~= [translateArgument(arg_iter.get())];
        }
        return result;
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
        arg.type = translateType(cppDecl.getType());

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

        auto declarator = new Declarator();
        declarator.name = nameFromDecl(cppDecl);
        var.declarators ~= [declarator];
        var.type = translateType(cppDecl.getType());

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
};

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
    // TODO rethink this entire method for libdparse
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

        TranslatorVisitor visitor = new TranslatorVisitor("", "");
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

    resolveTypes();
}

void determineRecordStrategy(unknown.Type* cppType)
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
};

void resolveTypes()
{
    // During the initial translation phase, we know that a variable is an
    // instance of the type associated with a particular declaration, but we
    // haven't decided what the fully qualified name of that type is yet.
    // createAllTypes build the fully qualified names, and this function
    // goes through the list of deferred types and fills them in.
}