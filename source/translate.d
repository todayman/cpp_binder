/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2014 Paul O'Neil <redballoon36@gmail.com>
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

module translate;

import std.conv : to;
import std.stdio : stdout, stderr;

static import binder;
static import dlang_decls;
static import unknown;
import manual_types;

private dlang_decls.Type[unknown.Type*] translated_types;
private dlang_decls.Declaration[void*] translated;
private dlang_decls.Type[unknown.Type*] resolved_replacements;
// TODO ^ what's the difference between this and translated types?
private dlang_decls.Type[string] types_by_name;

dlang_decls.Type translateType(unknown.Type* cppType);

void determineRecordStrategy(unknown.Type* cppType);

Result CHECK_FOR_DECL(Result, Input)(Input cppDecl)
{
    if (cast(void*)cppDecl in translated)
    {
        return cast(Result)translated[cast(void*)cppDecl];
        // ^ This cast failing is a huge internal programmer error
    }
    return null;
}

private dlang_decls.Linkage translateLinkage(T)(T cppDecl)
{
    dlang_decls.Linkage result;
    clang.LanguageLinkage linkage = cppDecl.getLinkLanguage();
    if (cppDecl.getLinkLanguage() == manual_types.LanguageLinkage.CLanguageLinkage)
    {
        result.lang = dlang_decls.Language.C;
    }
    else if (cppDecl.getLinkLanguage() == clang.LanguageLinkage.CXXLanguageLinkage)
    {
        result.lang = dlang_decls.Language.CPP;
    }
    else if (cppDecl.getLinkLanguage() == clang.LanguageLinkage.NoLanguageLinkage)
    {
        cppDecl.dump();
        stderr.writeln("WARNING: symbol has no language linkage.  Assuming C++.");
        result.lang = dlang_decls.Language.CPP;
    }
    else {
        stderr.writeln("Didn't recognize linkage");
        assert(0);
    }
    return result;
}

private dlang_decls.Visibility translateVisibility(unknown.Visibility access)
{
    final switch (access)
    {
        case unknown.Visibility.UNSET:
            throw new Exception("Unset visibility");
        case unknown.Visibility.PUBLIC:
            return dlang_decls.Visibility.PUBLIC;
        case unknown.Visibility.PRIVATE:
            return dlang_decls.Visibility.PRIVATE;
        case unknown.Visibility.PROTECTED:
            return dlang_decls.Visibility.PROTECTED;
        case unknown.Visibility.EXPORT:
            return dlang_decls.Visibility.EXPORT;
        case unknown.Visibility.PACKAGE:
            return dlang_decls.Visibility.PACKAGE;
    }
}

class OverloadedOperatorError : Exception
{
    this()
    {
        super("Cannot translate overloaded operators.");
    }
};

// Would kind of like a WhiteHole for these
class TranslatorVisitor : unknown.DeclarationVisitor
{
    string parent_package_name;
    string namespace_path;
    public:
    dlang_decls.Declaration last_result;

    public:
    this(string parent, string nsp)
    {
        namespace_path = nsp;
        last_result = null;
    }

    dlang_decls.Function translateFunction(unknown.FunctionDeclaration cppDecl)
    {
        dlang_decls.Function short_circuit = CHECK_FOR_DECL!(dlang_decls.Function)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        dlang_decls.Function d_decl = new dlang_decls.Function(cppDecl);
        // Set the linkage attributes for this function
        d_decl.linkage = translateLinkage(cppDecl);
        d_decl.linkage.name_space = namespace_path;

        binder.binder.string target_name = cppDecl.getTargetName();
        if (target_name.size())
        {
            d_decl.name = binder.toDString(target_name);
        }
        else
        {
            throw new Exception("Function declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        d_decl.return_type = translateType(cppDecl.getReturnType());

        for (auto arg_iter = cppDecl.getArgumentBegin(), arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance())
        {
            // FIXME check these types
            d_decl.arguments ~= [translateArgument(arg_iter.get())];
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
            last_result = translateFunction(cppDecl);
        }
    }

    dlang_decls.Module translateNamespace(unknown.NamespaceDeclaration cppDecl)
    {
        // TODO I probably shouldn't even be doing this,
        // just looping over all of the items in the namespace and setting the
        // target_module attribute (if it's not already set),
        // and then visiting those nodes.  Then the modules / packages get
        // created when something goes in them.
        dlang_decls.Module mod;
        if (cast(void*)cppDecl in translated)
        {
            dlang_decls.Declaration search = translated[cast(void*)cppDecl];
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

        string this_package_name = parent_package_name ~ "." ~ mod.getName();
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
        string this_namespace_path = namespace_path ~ "::" ~ mod.getName();
        // visit and translate all of the children
        for (unknown.DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             !children_iter.equals(children_end);
             children_iter.advance())
        {
            try {
                TranslatorVisitor subpackage_visitor = new TranslatorVisitor(this_package_name, this_namespace_path);
                children_iter.get().visit(subpackage_visitor);

                // not all translations get placed, and some are unwrappable,
                if (subpackage_visitor.last_result)
                {
                    placeIntoTargetModule(children_iter.get(), subpackage_visitor.last_result);
                }
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

    dlang_decls.Struct buildStruct(unknown.RecordDeclaration cppDecl)
    {
        dlang_decls.Struct short_circuit = CHECK_FOR_DECL!(dlang_decls.Struct)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        dlang_decls.Struct result = new dlang_decls.Struct(cppDecl);
        translated[cast(void*)cppDecl] = result;
        translated_types[cppDecl.getType()] = result;
        result.name = binder.toDString(cppDecl.getTargetName());

        // Set the linkage attributes for this struct
        // This only matters for methods
        result.linkage.lang = dlang_decls.Language.CPP;
        result.linkage.name_space = namespace_path;

        for (unknown.FieldIterator iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             !iter.equals(finish);
             iter.advance())
        {
            dlang_decls.Field field = translateField(iter.get());
            result.insert(field);
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
            dlang_decls.Method method;
            try {
                // FIXME double dereference? really?
                method = translateMethod(iter.get());
            }
            catch (Exception exc)
            {
                stderr.writeln("ERROR: Cannot translate method ", cppDecl.getSourceName(), "::", cpp_method.getSourceName(), ", skipping it");
                stderr.writeln("\t", exc.msg);
                continue;
            }
            if (method.kind == dlang_decls.Method.Kind.VIRTUAL)
            {
                throw new Exception("Methods on structs cannot be virtual!");
            }
            result.methods ~= (method);
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

    dlang_decls.Interface buildInterface(unknown.RecordDeclaration cppDecl)
    {
        dlang_decls.Interface short_circuit = CHECK_FOR_DECL!(dlang_decls.Interface)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        dlang_decls.Interface result = new dlang_decls.Interface(cppDecl);
        translated[cast(void*)cppDecl] = result;
        // TODO It looks like I elided this check in buildStruct,
        // Can I elide it here also, or does it need to go back in above?
        if (cppDecl.getType() in translated_types)
        {
            return cast(dlang_decls.Interface)translated_types[cppDecl.getType()];
        }
        translated_types[cppDecl.getType()] = result;
        result.name = binder.toDString(cppDecl.getTargetName());

        // Set the linkage attributes for this interface
        // This only matters for methods
        result.linkage.lang = dlang_decls.Language.CPP;
        result.linkage.name_space = namespace_path;

        // Find the superclasses of this interface
        for( unknown.SuperclassIterator iter = cppDecl.getSuperclassBegin(),
                finish = cppDecl.getSuperclassEnd();
             !iter.equals(finish);
             iter.advance() )
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
            dlang_decls.Type superType = translateType(superclass.base);
            dlang_decls.Interface superInterface =
                cast(dlang_decls.Interface)superType;
            dlang_decls.StringType superString =  // TODO is this really OK?
                cast(dlang_decls.StringType)superType;
            if (!superInterface && !superString)
            {
                throw new Exception("Superclass of an interface is not an interface.");
            }
            result.superclasses ~= [superInterface];
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
                dlang_decls.Method method = translateMethod(iter.get());
                if (dlang_decls.Method.Kind.FINAL == method.kind)
                {
                    throw new Exception("Methods on interfaces must be virtual!");
                }
                result.methods ~= [method];
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
                last_result = buildStruct(cppDecl);
                break;
            case unknown.Strategy.INTERFACE:
                last_result = buildInterface(cppDecl);
                break;
            default:
                stderr.writeln("Strategy is: ", cppDecl.getType().getStrategy());
                throw new Exception("I don't know how to translate records using strategies other than STRUCT and INTERFACE yet.");
        }
    }

    dlang_decls.TypeAlias translateTypedef(unknown.TypedefDeclaration cppDecl)
    {
        dlang_decls.TypeAlias short_circuit = CHECK_FOR_DECL!(dlang_decls.TypeAlias)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        dlang_decls.TypeAlias result = new dlang_decls.TypeAlias(cppDecl);
        translated[cast(void*)cppDecl] = result;
        translated_types[cppDecl.getType()] = result;
        result.name = binder.toDString(cppDecl.getTargetName());
        result.target_type = translateType(cppDecl.getTargetType());

        return result;
    }
    extern(C++) override
    void visitTypedef(unknown.TypedefDeclaration cppDecl)
    {
        last_result = translateTypedef(cppDecl);
    }

    dlang_decls.Enum translateEnum(unknown.EnumDeclaration cppDecl)
    {
        dlang_decls.Enum short_circuit = CHECK_FOR_DECL!(dlang_decls.Enum)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        dlang_decls.Enum result = new dlang_decls.Enum(cppDecl);
        translated[cast(void*)cppDecl] = result;
        translated_types[cppDecl.getType()] = result;

        unknown.Type * cppType = cppDecl.getType();
        result.type = translateType(cppType);
        result.name = binder.toDString(cppDecl.getTargetName());
        try {
            result.visibility = translateVisibility(cppDecl.getVisibility());
        }
        catch (Exception e)  // FIXME also catches thing that were logic error
        {
            // catch when visibility is unset.
            // FIXME is this the right thing?
            result.visibility = dlang_decls.Visibility.PUBLIC;
        }

        // visit and translate all of the constants
        for( unknown.DeclarationIterator children_iter = cppDecl.getChildBegin(),
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

            result.values ~= [translateEnumConstant(constant)];
        }

        return result;
    }
    extern(C++) override void visitEnum(unknown.EnumDeclaration cppDecl)
    {
        last_result = translateEnum(cppDecl);
    }

    dlang_decls.EnumConstant translateEnumConstant(unknown.EnumConstantDeclaration cppDecl)
    {
        dlang_decls.EnumConstant short_circuit = CHECK_FOR_DECL!(dlang_decls.EnumConstant)(cppDecl);
        if (short_circuit !is null) return short_circuit;
        dlang_decls.EnumConstant result = new dlang_decls.EnumConstant(cppDecl);
        result.name = binder.toDString(cppDecl.getTargetName()); // TODO remove prefix
        result.value = cppDecl.getLLValue();

        return result;
    }
    extern(C++) override void visitEnumConstant(unknown.EnumConstantDeclaration)
    {
        // Getting here means that there is an enum constant declaration
        // outside of an enum declaration, since visitEnum calls
        // translateEnumConstant directly.
        throw new Error("Attempted to translate an enum constant directly, instead of via an enum.");
    }

    dlang_decls.Field translateField(unknown.FieldDeclaration cppDecl)
    {
        dlang_decls.Field short_circuit = CHECK_FOR_DECL!(dlang_decls.Field)(cppDecl);
        if (short_circuit !is null) return short_circuit;
        dlang_decls.Field result = new dlang_decls.Field(cppDecl);
        result.name = binder.toDString(cppDecl.getTargetName());
        result.type = translateType(cppDecl.getType());
        result.visibility = translateVisibility(cppDecl.getVisibility());
        return result;
    }
    extern(C++) override void visitField(unknown.FieldDeclaration)
    {
        // Getting here means that there is a field declaration
        // outside of a record declaration, since the struct / interface building
        // functions call translateField directly.
        throw new Error("Attempted to translate a field directly, instead of via a record.");
    }

    dlang_decls.Union translateUnion(unknown.UnionDeclaration cppDecl)
    {
        dlang_decls.Union short_circuit = CHECK_FOR_DECL!(dlang_decls.Union)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        dlang_decls.Union result = new dlang_decls.Union(cppDecl);
        translated[cast(void*)cppDecl] = result;
        translated_types[cppDecl.getType()] = result;
        result.name = binder.toDString(cppDecl.getTargetName());

        for (unknown.FieldIterator iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             !iter.equals(finish);
             iter.advance() )
        {
            dlang_decls.Field field = translateField(iter.get());
            result.insert(field);
        }

        // TODO static methods and other things?
        return result;
    }
    extern(C++) override void visitUnion(unknown.UnionDeclaration cppDecl)
    {
        last_result = translateUnion(cppDecl);
    }

    dlang_decls.Method translateMethod(unknown.MethodDeclaration cppDecl)
    {
        dlang_decls.Method short_circuit = CHECK_FOR_DECL!(dlang_decls.Method)(cppDecl);
        if (short_circuit !is null) return short_circuit;

        if (cppDecl.isOverloadedOperator())
        {
            throw new OverloadedOperatorError();
        }

        dlang_decls.Method result = new dlang_decls.Method(cppDecl);

        if (cppDecl.isStatic())
        {
            result.kind = dlang_decls.Method.Kind.STATIC;
        }
        else if (cppDecl.isVirtual())
        {
            result.kind = dlang_decls.Method.Kind.VIRTUAL;
        }
        else {
            result.kind = dlang_decls.Method.Kind.FINAL;
        }

        if (cppDecl.getTargetName().size())
        {
            result.name = binder.toDString(cppDecl.getTargetName());
        }
        else
        {
            throw new Exception("Method declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        result.return_type = translateType(cppDecl.getReturnType());
        if (cppDecl.getVisibility() == unknown.Visibility.UNSET)
            cppDecl.dump();
        result.visibility = translateVisibility(cppDecl.getVisibility());

        for (unknown.ArgumentIterator arg_iter = cppDecl.getArgumentBegin(),
                arg_end = cppDecl.getArgumentEnd();
             !arg_iter.equals(arg_end);
             arg_iter.advance() )
        {
            // FIXME double dereference? really?
            result.arguments ~= [translateArgument(arg_iter.get())];
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

    dlang_decls.Argument translateArgument(unknown.ArgumentDeclaration cppDecl)
    {
        dlang_decls.Argument short_circuit = CHECK_FOR_DECL!(dlang_decls.Argument)(cppDecl);
        if (short_circuit !is null) return short_circuit;
        dlang_decls.Argument arg = new dlang_decls.Argument(cppDecl);
        arg.name = binder.toDString(cppDecl.getTargetName());
        arg.type = translateType(cppDecl.getType());

        return arg;
    }
    extern(C++) override void visitArgument(unknown.ArgumentDeclaration cppDecl)
    {
        last_result = translateArgument(cppDecl);
    }

    dlang_decls.Variable translateVariable(unknown.VariableDeclaration cppDecl)
    {
        dlang_decls.Variable short_circuit = CHECK_FOR_DECL!(dlang_decls.Variable)(cppDecl);
        if (short_circuit !is null) return short_circuit;
        dlang_decls.Variable var = new dlang_decls.Variable(cppDecl);

        var.linkage = translateLinkage(cppDecl);
        var.linkage.name_space = namespace_path;
        binder.binder.string target_name = cppDecl.getTargetName();
        var.name = binder.toDString(target_name);
        var.type = translateType(cppDecl.getType());

        return var;
    }
    extern(C++) override void visitVariable(unknown.VariableDeclaration cppDecl)
    {
        last_result = translateVariable(cppDecl);
    }
    extern(C++) override void visitUnwrappable(unknown.UnwrappableDeclaration)
    {
        // Cannot wrap unwrappable declarations, ;)
    }
};

private void placeIntoTargetModule(unknown.Declaration declaration, dlang_decls.Declaration translation)
{
    // FIXME sometimes this gets called multiple times on the same declaration,
    // so it will get output multiple times, which is clearly wrong
    // It happens because there are multiple declarations of the same type
    // (e.g. forward and normal), that have the same translation
    if (translation.parent)
    {
        return;
    }
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
    dlang_decls.Module mod = dlang_decls.rootPackage.getOrCreateModulePath(target_module);
    if (translation)
    {
        mod.insert(translation);
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
            dlang_decls.Declaration translation;
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
    //delete[] freeDeclarations;
}


dlang_decls.Type replacePointer(unknown.Type* cppType);
dlang_decls.Type replaceReference(unknown.Type* cppType);
dlang_decls.Type replaceTypedef(unknown.Type* cppType);
dlang_decls.Type replaceEnum(unknown.Type* cppType);
dlang_decls.Type replaceFunction(unknown.Type* cppType);
dlang_decls.Type replaceUnion(unknown.Type* cppType);

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
            // FIXME empty string means resolve to an actual AST type, not a string?
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

class NoDefinitionException : Exception
{
    this(unknown.Declaration decl)
    {
      super(to!string(decl.getSourceName().c_str()) ~ " has no definition, so I cannot determine a translation strategy.");
    }
};

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

dlang_decls.Type replaceType(unknown.Type* cppType)
{
    dlang_decls.Type result;
    string replacement_name = binder.toDString(cppType.getReplacement());
    if (replacement_name.length > 0)
    {
        if (replacement_name !in types_by_name)
        {
            result = new dlang_decls.StringType(replacement_name);
            types_by_name[replacement_name] = result;

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
        if (cppType in resolved_replacements)
        {
            // FIXME do without the second lookup
            return resolved_replacements[cppType];
        }

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
                return replacePointer(cppType);
            case unknown.Type.Kind.Reference:
                return replaceReference(cppType);
            case unknown.Type.Kind.Typedef:
                return replaceTypedef(cppType);
            case unknown.Type.Kind.Enum:
                return replaceEnum(cppType);
            case unknown.Type.Kind.Function:
                return replaceFunction(cppType);

            case unknown.Type.Kind.Record:
                // TODO figure out (again) why this is an error and add
                // a comment explaining that
                throw new Error("Called replaceType on a Record");
                break;
            case unknown.Type.Kind.Union:
                return replaceUnion(cppType);
                break;
            case unknown.Type.Kind.Array:
                // TODO
                throw new Error("replaceType on Arrays is not implemented yet.");
                break;
            case unknown.Type.Kind.Vector:
                throw new Error("replaceType on Vector types is not implemented yet.");
                break;
        }

    }
}

dlang_decls.Type replacePointerOrReference(unknown.Type* cppType, dlang_decls.PointerType.PointerOrRef ptr_or_ref)
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

    dlang_decls.Type result;
    if (target_is_reference_type)
    {
        result = translateType(target_type);
    }
    else
    {
        dlang_decls.Type translated_pointee_type = translateType(target_type);
        result = new dlang_decls.PointerType(translated_pointee_type, ptr_or_ref);
    }

    return result;
}

dlang_decls.Type replacePointer(unknown.Type* cppType)
{
    return replacePointerOrReference(cppType, dlang_decls.PointerType.PointerOrRef.POINTER);
}
dlang_decls.Type replaceReference(unknown.Type* cppType)
{
    return replacePointerOrReference(cppType, dlang_decls.PointerType.PointerOrRef.REFERENCE);
}

dlang_decls.Type replaceTypedef(unknown.Type* cppType)
{
    unknown.TypedefDeclaration cppDecl = cppType.getTypedefDeclaration();
    dlang_decls.Type result;
    if (cast(void*)cppDecl !in translated)
    {
        TranslatorVisitor visitor = new TranslatorVisitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = visitor.translateTypedef(cppDecl);
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = cast(dlang_decls.Type)translated[cast(void*)cppDecl];
    }

    return result;
}
// FIXME There's a way to generalize this and combine it with replaceTypedef,
// but I don't see it upon cursory inspection, so I'll get to it later.
dlang_decls.Type replaceEnum(unknown.Type* cppType)
{
    unknown.EnumDeclaration cppDecl = cppType.getEnumDeclaration;
    dlang_decls.Type result;
    if (cast(void*)cppDecl !in translated)
    {
        TranslatorVisitor visitor = new TranslatorVisitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = visitor.translateEnum(cppDecl);
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = cast(dlang_decls.Type)translated[cast(void*)cppDecl];
    }

    return result;
}

dlang_decls.Type replaceFunction(unknown.Type*)
{
    // Needed for translating function types, but not declarations,
    // so I'm putting it off until later
    throw new Error("Translation of function types is not implemented yet.");
}

// FIXME There's a way to generalize this and combine it with replaceTypedef,
// but I don't see it upon cursory inspection, so I'll get to it later.
dlang_decls.Type replaceUnion(unknown.Type* cppType)
{
    unknown.UnionDeclaration cppDecl = cppType.getUnionDeclaration();
    dlang_decls.Type result;
    if (cast(void*)cppDecl !in translated)
    {
        TranslatorVisitor visitor = new TranslatorVisitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = visitor.translateUnion(cppDecl);
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = cast(dlang_decls.Type)translated[cast(void*)cppDecl];
    }

    return result;
}

// TODO combine with replaceEnum and replaceTypedef?
private dlang_decls.Type generateStruct(unknown.Type* cppType)
{
    if (cppType.getKind() != unknown.Type.Kind.Record)
    {
        throw new Error("Attempted to generate a struct from a non-record type.");
    }

    unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();

    dlang_decls.Type result;
    if (cast(void*)cppDecl !in translated)
    {
        TranslatorVisitor visitor = new TranslatorVisitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = visitor.buildStruct(cppDecl);
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = cast(dlang_decls.Type)translated[cast(void*)cppDecl];
    }

    return result;
}

private dlang_decls.Type generateInterface(unknown.Type* cppType)
{
    if (cppType.getKind() != unknown.Type.Kind.Record)
    {
        throw new Error("Attempted to generate an interface from a non-record type.");
    }

    unknown.RecordDeclaration cppDecl = cppType.getRecordDeclaration();

    dlang_decls.Type result;
    if (cast(void*)cppDecl !in translated)
    {
        TranslatorVisitor visitor = new TranslatorVisitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = visitor.buildInterface(cppDecl);
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = cast(dlang_decls.Type)translated[cast(void*)cppDecl];
    }

    return result;
}

dlang_decls.Type translateType(unknown.Type* cppType)
{
    if (cppType in translated_types)
    {
        return translated_types[cppType];
    }
    else
    {
        dlang_decls.Type result;
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
                result = generateStruct(cppType);
                break;
            case unknown.Strategy.INTERFACE:
                result = generateInterface(cppType);
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
            throw new Exception("Cannot translate type with strategy " ~ cppType.getStrategy().stringof);
        }
        return result;
    }
}
