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

#include <iostream>
#include <unordered_map>

#include "cpp_decl.hpp"
#include "dlang_decls.hpp"

static std::unordered_map<Type*, std::shared_ptr<dlang::Type>> translated_types;
static std::unordered_map<Declaration*, std::shared_ptr<dlang::Declaration>> translated;

std::shared_ptr<dlang::Type> translateType(Type* cppType);

void determineRecordStrategy(Type* cppType);

#define CHECK_FOR_DECL(x) \
        auto search = translated.find(static_cast<Declaration*>(&cppDecl)); \
        if( search != translated.end() ) \
        { \
            return std::dynamic_pointer_cast<dlang::x>(search->second); \
        }
// ^ This cast failing is a huge internal programmer error

template<typename T>
static dlang::Linkage translateLinkage(T& cppDecl)
{
    dlang::Linkage result;
    if( cppDecl.getLinkLanguage() == clang::CLanguageLinkage )
    {
        result.lang = dlang::LANG_C;
    }
    else if( cppDecl.getLinkLanguage() == clang::CXXLanguageLinkage )
    {
        result.lang = dlang::LANG_CPP;
    }
    else if( cppDecl.getLinkLanguage() == clang::NoLanguageLinkage )
    {
        cppDecl.decl()->dump();
        std::cerr << "WARNING: symbol has no language linkage.  Assuming C++.\n";
        result.lang = dlang::LANG_CPP;
    }
    return result;
}

static dlang::Visibility translateVisibility(::Visibility access)
{
    switch( access )
    {
        case ::UNSET:
            throw std::runtime_error("Unset visibility");
        case ::PUBLIC:
            return dlang::PUBLIC;
        case ::PRIVATE:
            return dlang::PRIVATE;
        case ::PROTECTED:
            return dlang::PROTECTED;
        case ::EXPORT:
            return dlang::EXPORT;
        case ::PACKAGE:
            return dlang::PACKAGE;
        default:
            throw 32;
    }
}

class TranslatorVisitor;
static void placeIntoTargetModule(Declaration* declaration, std::shared_ptr<dlang::Declaration> translation);

// Would kind of like a WhiteHole for these
class TranslatorVisitor : public DeclarationVisitor
{
    string parent_package_name;
    string namespace_path;
    public:
    std::shared_ptr<dlang::Declaration> last_result;

    explicit TranslatorVisitor(string parent, string nsp)
        : parent_package_name(parent), namespace_path(nsp), last_result()
    { }

    std::shared_ptr<dlang::Function> translateFunction(FunctionDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Function)

        std::shared_ptr<dlang::Function> d_decl = std::make_shared<dlang::Function>(&cppDecl);
        // Set the linkage attributes for this function
        d_decl->linkage = translateLinkage(cppDecl);
        d_decl->linkage.name_space = namespace_path;

        if( cppDecl.getTargetName().size() )
        {
            d_decl->name = cppDecl.getTargetName();
        }
        else
        {
            throw std::runtime_error("Function declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        d_decl->return_type = translateType(cppDecl.getReturnType());

        for( auto arg_iter = cppDecl.getArgumentBegin(), arg_end = cppDecl.getArgumentEnd();
             arg_iter != arg_end;
             ++arg_iter )
        {
            // FIXME double dereference? really?
            d_decl->arguments.push_back(translateArgument(**arg_iter));
        }
        return d_decl;
    }
    virtual void visitFunction(FunctionDeclaration& cppDecl) override
    {
        if( reinterpret_cast<const clang::FunctionDecl*>(cppDecl.decl())->isOverloadedOperator() )
        {
            std::cout << "ERROR: Cannot translate overloaded operator.\n";
        }
        else
        {
            last_result = std::static_pointer_cast<dlang::Declaration>(translateFunction(cppDecl));
        }
    }

    std::shared_ptr<dlang::Module> translateNamespace(NamespaceDeclaration& cppDecl)
    {
        // TODO I probably shouldn't even be doing this,
        // just looping over all of the items in the namespace and setting the
        // target_module attribute (if it's not already set),
        // and then visiting those nodes.  Then the modules / packages get
        // created when something goes in them.
        auto search = translated.find(static_cast<Declaration*>(&cppDecl));
        std::shared_ptr<dlang::Module> module;
        if( search != translated.end() )
        {
            // This cast failing means that we previously translated this
            // namespace as something other than a module, which is a really
            // bad logic error.
            module = std::dynamic_pointer_cast<dlang::Module>(search->second);
            if( !module )
            {
                throw std::logic_error("Translated a namespace to something other than a module.");
            }
        }
        else
        {
            module = std::make_shared<dlang::Module>(cppDecl.getTargetName());
        }

        string this_package_name = parent_package_name + "." + module->getName();
        for( DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             children_iter != children_end;
             ++children_iter )
        {
            if( !(*children_iter)->isTargetModuleSet() )
            {
                (*children_iter)->setTargetModule(this_package_name);
            }
        }

        // This is the translated name, but really I want the C++ name
        string this_namespace_path = namespace_path + "::" + module->getName();
        // visit and translate all of the children
        for( DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             children_iter != children_end;
             ++children_iter )
        {
            try {
                TranslatorVisitor subpackage_visitor(this_package_name, this_namespace_path);
                (*children_iter)->visit(subpackage_visitor);

                // not all translations get placed, and some are unwrappable,
                if( subpackage_visitor.last_result )
                {
                    placeIntoTargetModule(*children_iter, subpackage_visitor.last_result);
                }
            }
            catch( std::runtime_error& exc )
            {
                (*children_iter)->decl()->dump();
                std::cerr << "ERROR: " << exc.what() << "\n";
            }
        }

        return module;
    }

    virtual void visitNamespace(NamespaceDeclaration& cppDecl) override
    {
        translateNamespace(cppDecl);
        last_result = std::shared_ptr<dlang::Declaration>();
    }

    std::shared_ptr<dlang::Struct> buildStruct(RecordDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Struct)

        std::shared_ptr<dlang::Struct> result = std::make_shared<dlang::Struct>(&cppDecl);
        translated.insert(std::make_pair(&cppDecl, result));
        translated_types.insert(std::make_pair(cppDecl.getType(), result));
        result->name = cppDecl.getTargetName();

        // Set the linkage attributes for this struct
        // This only matters for methods
        result->linkage.lang = dlang::LANG_CPP;
        result->linkage.name_space = namespace_path;

        for( auto iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             iter != finish;
             ++iter )
        {
            // FIXME double dereference? really?
            std::shared_ptr<dlang::Field> field = translateField(**iter);
            result->insert(field);
        }

        for( auto iter = cppDecl.getMethodBegin(),
                  finish = cppDecl.getMethodEnd();
             iter != finish;
             ++iter )
        {
            // sometimes, e.g. for implicit destructors, the lookup from clang
            // type to my types fails.  So we should skip those.
            MethodDeclaration* cpp_method = *iter;
            if( !cpp_method || !cpp_method->getShouldBind() )
                continue;
            std::shared_ptr<dlang::Method> method;
            try {
                // FIXME double dereference? really?
                method = translateMethod(**iter);
            }
            catch( std::runtime_error& exc )
            {
                std::cerr << "ERROR: Cannot translate method " << cppDecl.getSourceName() << "::" << cpp_method->getSourceName() << ", skipping it\n";
                continue;
            }
            if( method->kind == dlang::Method::VIRTUAL )
            {
                throw std::runtime_error("Methods on structs cannot be virtual!");
            }
            result->methods.push_back(method);
        }

        // TODO static methods and other things
        for( auto iter = cppDecl.getChildBegin(),
                finish = cppDecl.getChildEnd();
            iter != finish;
            ++iter )
        {
            if( EnumDeclaration* enumDecl = dynamic_cast<EnumDeclaration*>(*iter) )
            {
                result->insert(translateEnum(*enumDecl));
            }
        }
        return result;
    }

    std::shared_ptr<dlang::Interface> buildInterface(RecordDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Interface)

        std::shared_ptr<dlang::Interface> result = std::make_shared<dlang::Interface>(&cppDecl);
        translated.insert(std::make_pair(&cppDecl, result));
        translated_types.insert(std::make_pair(cppDecl.getType(), result));
        result->name = cppDecl.getTargetName();

        // Set the linkage attributes for this interface
        // This only matters for methods
        result->linkage.lang = dlang::LANG_CPP;
        result->linkage.name_space = namespace_path;

        // Find the superclasses of this interface
        for( auto iter = cppDecl.getSuperclassBegin(),
                finish = cppDecl.getSuperclassEnd();
             iter != finish;
             ++iter )
        {
            Superclass * super = *iter;
            if( super->visibility != PUBLIC )
            {
                throw std::runtime_error("Don't know how to translate non-public inheritance of interfaces.");
            }
            if( super->isVirtual )
            {
                throw std::runtime_error("Don't know how to translate virtual inheritance of interfaces.");
            }
            std::shared_ptr<dlang::Type> superType = translateType(super->base);
            std::shared_ptr<dlang::Interface> superInterface =
                std::dynamic_pointer_cast<dlang::Interface>(superType);
            if( !superInterface )
            {
                throw std::runtime_error("Superclass of an interface is not an interface.");
            }
            result->superclasses.push_back(superInterface);
        }

        for( auto iter = cppDecl.getMethodBegin(),
                  finish = cppDecl.getMethodEnd();
             iter != finish;
             ++iter )
        {
            // sometimes, e.g. for implicit destructors, the lookup from clang
            // type to my types fails.  So we should skip those.
            MethodDeclaration* cpp_method = *iter;
            if( !cpp_method || !cpp_method->getShouldBind() )
                continue;
            // FIXME double dereference? really?
            std::shared_ptr<dlang::Method> method = translateMethod(**iter);
            if( dlang::Method::FINAL == method->kind )
            {
                throw std::runtime_error("Methods on interfaces must be virtual!");
            }
            result->methods.push_back(method);
        }

        // TODO static methods and other things
        return result;
    }

    virtual void visitRecord(RecordDeclaration& cppDecl) override
    {
        determineRecordStrategy(cppDecl.getType());
        switch( cppDecl.getType()->getStrategy() )
        {
            case STRUCT:
                last_result = std::static_pointer_cast<dlang::Declaration>(buildStruct(cppDecl));
                break;
            case INTERFACE:
                last_result = std::static_pointer_cast<dlang::Declaration>(buildInterface(cppDecl));
                break;
            default:
                std::cerr << "Strategy is: " << cppDecl.getType()->getStrategy() << "\n";
                std::logic_error("I don't know how to translate records using strategies other than STRUCT and INTERFACE yet.");
        }
    }
    std::shared_ptr<dlang::TypeAlias> translateTypedef(TypedefDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(TypeAlias)

        std::shared_ptr<dlang::TypeAlias> result = std::make_shared<dlang::TypeAlias>(&cppDecl);
        result->name = cppDecl.getTargetName();
        result->target_type = translateType(cppDecl.getTargetType());

        return result;
    }
    virtual void visitTypedef(TypedefDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateTypedef(cppDecl));
    }

    std::shared_ptr<dlang::Enum> translateEnum(EnumDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Enum)

        std::shared_ptr<dlang::Enum> result = std::make_shared<dlang::Enum>(&cppDecl);

        result->type = translateType(cppDecl.getType());
        result->name = cppDecl.getTargetName();

        // visit and translate all of the constants
        for( DeclarationIterator children_iter = cppDecl.getChildBegin(),
                children_end = cppDecl.getChildEnd();
             children_iter != children_end;
             ++children_iter )
        {
            EnumConstantDeclaration* constant = dynamic_cast<EnumConstantDeclaration*>(*children_iter);
            if( !constant )
            {
                std::cout << "Error translating enum constant.\n";
                continue;
            }

            result->values.push_back(translateEnumConstant(*constant));
        }

        return result;
    }
    virtual void visitEnum(EnumDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateEnum(cppDecl));
    }

    std::shared_ptr<dlang::EnumConstant> translateEnumConstant(EnumConstantDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(EnumConstant)
        std::shared_ptr<dlang::EnumConstant> result = std::make_shared<dlang::EnumConstant>(&cppDecl);
        result->name = cppDecl.getTargetName(); // TODO remove prefix
        result->value = cppDecl.getValue();

        return result;
    }
    virtual void visitEnumConstant(EnumConstantDeclaration&) override
    {
        // Getting here means that there is an enum constant declaration
        // outside of an enum declaration, since visitEnum calls
        // translateEnumConstant directly.
        throw std::logic_error("Attempted to translate an enum constant directly, instead of via an enum.");
    }

    std::shared_ptr<dlang::Field> translateField(FieldDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Field)
        std::shared_ptr<dlang::Field> result = std::make_shared<dlang::Field>(&cppDecl);
        result->name = cppDecl.getTargetName();
        result->type = translateType(cppDecl.getType());
        result->visibility = translateVisibility(cppDecl.getVisibility());
        return result;
    }
    virtual void visitField(FieldDeclaration&) override
    {
        // Getting here means that there is a field declaration
        // outside of a record declaration, since the struct / interface building
        // functions call translateField directly.
        throw std::logic_error("Attempted to translate a field directly, instead of via a record.");
    }

    std::shared_ptr<dlang::Union> translateUnion(UnionDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Union)

        std::shared_ptr<dlang::Union> result = std::make_shared<dlang::Union>(&cppDecl);
        result->name = cppDecl.getTargetName();

        for( auto iter = cppDecl.getFieldBegin(),
                  finish = cppDecl.getFieldEnd();
             iter != finish;
             ++iter )
        {
            // FIXME double dereference? really?
            std::shared_ptr<dlang::Field> field = translateField(**iter);
            result->insert(field);
        }

        // TODO static methods and other things?
        return result;
    }
    virtual void visitUnion(UnionDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateUnion(cppDecl));
    }

    std::shared_ptr<dlang::Method> translateMethod(MethodDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Method)

        std::shared_ptr<dlang::Method> result = std::make_shared<dlang::Method>(&cppDecl);

        if( cppDecl.isStatic() )
        {
            result->kind = dlang::Method::STATIC;
        }
        else if( cppDecl.isVirtual() )
        {
            result->kind = dlang::Method::VIRTUAL;
        }
        else {
            result->kind = dlang::Method::FINAL;
        }

        if( cppDecl.getTargetName().size() )
        {
            result->name = cppDecl.getTargetName();
        }
        else
        {
            throw std::runtime_error("Method declaration doesn't have a target name.  This implies that it also didn't have a name in the C++ source.  This shouldn't happen.");
        }

        result->return_type = translateType(cppDecl.getReturnType());
        if( cppDecl.getVisibility() == UNSET )
            cppDecl.decl()->dump();
        result->visibility = translateVisibility(cppDecl.getVisibility());

        for( auto arg_iter = cppDecl.getArgumentBegin(), arg_end = cppDecl.getArgumentEnd();
             arg_iter != arg_end;
             ++arg_iter )
        {
            // FIXME double dereference? really?
            result->arguments.push_back(translateArgument(**arg_iter));
        }
        return result;
    }

    virtual void visitMethod(MethodDeclaration&) override
    {
        // Getting here means that there is a method declaration
        // outside of a record declaration, since the struct / interface building
        // functions call translateMethod directly.
        throw std::runtime_error("Attempting to translate a method as if it were top level, but methods are never top level.");
    }
    virtual void visitConstructor(ConstructorDeclaration&) override
    {
        // the C++ interface page on dlang.org says that D cannot call constructors
    }
    virtual void visitDestructor(DestructorDeclaration&) override
    {
        // the C++ interface page on dlang.org says that D cannot call destructors
    }

    std::shared_ptr<dlang::Argument> translateArgument(ArgumentDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Argument)
        std::shared_ptr<dlang::Argument> arg = std::make_shared<dlang::Argument>(&cppDecl);
        arg->name = cppDecl.getTargetName();
        arg->type = translateType(cppDecl.getType());

        return arg;
    }
    virtual void visitArgument(ArgumentDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateArgument(cppDecl));
    }

    std::shared_ptr<dlang::Variable> translateVariable(VariableDeclaration& cppDecl)
    {
        CHECK_FOR_DECL(Variable)
        std::shared_ptr<dlang::Variable> var = std::make_shared<dlang::Variable>(&cppDecl);

        var->linkage = translateLinkage(cppDecl);
        var->linkage.name_space = namespace_path;
        var->name = cppDecl.getTargetName();
        var->type = translateType(cppDecl.getType());

        return var;
    }
    virtual void visitVariable(VariableDeclaration& cppDecl) override
    {
        last_result = std::static_pointer_cast<dlang::Declaration>(translateVariable(cppDecl));
    }
    virtual void visitUnwrappable(UnwrappableDeclaration&) override
    {
        // Cannot wrap unwrappable declarations, ;)
    }
};

static void placeIntoTargetModule(Declaration* declaration, std::shared_ptr<dlang::Declaration> translation)
{
    // FIXME sometimes this gets called multiple times on the same declaration,
    // so it will get output multiple times, which is clearly wrong
    if( translation->parent )
    {
        throw std::logic_error("Attempted to place a declaration into a module twice.");
    }
    string target_module = declaration->getTargetModule();
    if( target_module.size() == 0 )
    {
        target_module = "unknown";
    }
    else
    {
        // Root package is named empty, so target modules may start with '.', as in
        // .std.stdio
        // '.' messes with the lookup, so take it out if it's there
        if( target_module.c_str()[0] == '.' )
        {
            target_module = string(target_module.begin() + 1, target_module.end());
        }
    }
    std::shared_ptr<dlang::Module> module = dlang::rootPackage->getOrCreateModulePath(target_module);
    if( translation )
    {
        module->insert(translation);
    }
}

void populateDAST()
{
    // May cause problems because root package won't check for empty path.
    for( auto declaration : DeclVisitor::getFreeDeclarations() )
    {
        if( !declaration->getShouldBind() )
        {
            continue;
        }

        TranslatorVisitor visitor("", "");
        try {
            std::shared_ptr<dlang::Declaration> translation;
            auto iter = translated.find(declaration);
            if( translated.end() == iter )
            {
                declaration->visit(visitor);
                translation = visitor.last_result;
            }
            else
            {
                translation = iter->second;
            }

            // some items, such as namespaces, don't need to be placed into a module
            // visiting them just translates their children and puts them in modules
            if( translation )
            {
                placeIntoTargetModule(declaration, translation);
            }
        }
        catch( std::runtime_error& exc )
        {
            declaration->decl()->dump();
            std::cerr << "ERROR: " <<  exc.what() << "\n";
        }

    }
}

std::unordered_map<Type*, std::shared_ptr<dlang::Type>> tranlsated_types;
std::unordered_map<string, std::shared_ptr<dlang::Type>> types_by_name;
std::unordered_map<Type*, std::shared_ptr<dlang::Type>> resolved_replacements;

std::shared_ptr<dlang::Type> replacePointer(Type* cppType);
std::shared_ptr<dlang::Type> replaceReference(Type* cppType);
std::shared_ptr<dlang::Type> replaceTypedef(Type* cppType);
std::shared_ptr<dlang::Type> replaceEnum(Type* cppType);
std::shared_ptr<dlang::Type> replaceFunction(Type* cppType);
std::shared_ptr<dlang::Type> replaceUnion(Type* cppType);

void determineStrategy(Type* cppType)
{
    if( cppType->getStrategy() != UNKNOWN )
    {
        return;
    }

    switch( cppType->getKind() )
    {
        case Type::Invalid:
            cppType->cppType()->dump();
            throw std::runtime_error("Attempting to determine strategy for invalid type.");
            break;
        case Type::Builtin:
            std::cerr << "I don't know how to translate the builtin C++ type:\n";
            cppType->cppType()->dump();
            std::cerr << "\n";
            std::runtime_error("Cannot translate builtin.");
            break;
        case Type::Pointer:
        case Type::Reference:
        case Type::Typedef:
        case Type::Enum:
        case Type::Function:
            cppType->chooseReplaceStrategy(""); // FIXME empty string means resolve to an actual AST type, not a string?
            break;

        case Type::Record:
            determineRecordStrategy(cppType);
            break;
        case Type::Union:
            cppType->chooseReplaceStrategy(""); // FIXME see note for Function
            break;
        case Type::Array:
            break;
        case Type::Vector:
            throw std::logic_error("Cannot translate vector (e.g. SSE, AVX) types.");
    }
}

struct NoDefinitionException : public std::runtime_error
{
    NoDefinitionException(Declaration* decl)
      : std::runtime_error((decl->getSourceName() + " has no definition, so I cannot determine a translation strategy.").c_str())
    { }
};

void determineRecordStrategy(Type* cppType)
{
    // There are some paths that don't come through determineStrategy,
    // so filter those out.
    if( cppType->getStrategy() != UNKNOWN )
    {
        return;
    }

    // First algorithm:
    // If the record has any virtual functions, then map it as an interface,
    // otherwise keep it as a struct
    // This ignores things like the struct default constructor,
    // so it's not perfect

    const clang::RecordType * cpp_record = cppType->cppType()->castAs<clang::RecordType>();
    RecordDeclaration* cpp_decl =
        dynamic_cast<RecordDeclaration*>(
                DeclVisitor::getDeclarations().find(cpp_record->getDecl())->second
                );

    if( !isCXXRecord(cpp_decl->decl()) )
    {
        cppType->setStrategy(STRUCT);
    }
    else
    {
        //std::cout << "Determining strategy for " << cppType->getName()
        std::cerr << "Determinining strategy for: " << cpp_decl->getSourceName() << " (" << cpp_record << ")\n";
        const clang::CXXRecordDecl* cxxRecord = reinterpret_cast<const clang::CXXRecordDecl*>(cpp_decl->decl());
        if( !cxxRecord->hasDefinition() ) {
            throw NoDefinitionException(cpp_decl);
        }

        if( cxxRecord->isDynamicClass() )
        {
            cppType->setStrategy(INTERFACE);
            std::cerr << "\tChose INTERFACE\n";
        }
        else
        {
            cppType->setStrategy(STRUCT);
            std::cerr << "\tChose STRUCT\n";
        }
    }
}

std::shared_ptr<dlang::Type> replaceType(Type* cppType)
{
    std::shared_ptr<dlang::Type> result;
    const string& replacement_name = cppType->getReplacement();
    if( replacement_name.size() > 0 )
    {
        auto search_result = types_by_name.find(replacement_name);
        if( search_result == types_by_name.end() )
        {
            result = std::shared_ptr<dlang::Type>(new dlang::StringType(replacement_name));
            types_by_name.insert(std::make_pair(replacement_name, result));
        }
        else
        {
            result = search_result->second;
        }

        return result;
    }
    else
    {
        auto replacement_search = resolved_replacements.find(cppType);
        if( replacement_search != resolved_replacements.end() )
        {
            return replacement_search->second;
        }

        switch( cppType->getKind() )
        {
            case Type::Invalid:
                throw 16;
                break;
            case Type::Builtin:
                throw 18;
            case Type::Pointer:
                return replacePointer(cppType);
            case Type::Reference:
                return replaceReference(cppType);
            case Type::Typedef:
                return replaceTypedef(cppType);
            case Type::Enum:
                return replaceEnum(cppType);
            case Type::Function:
                return replaceFunction(cppType);

            case Type::Record:
                throw 24;
                break;
            case Type::Union:
                return replaceUnion(cppType);
                break;
            case Type::Array:
                // TODO
                throw 19;
                break;
            case Type::Vector:
                throw 17;
        }

    }
}

static std::shared_ptr<dlang::Type> replacePointerOrReference(Type* cppType, dlang::PointerType::PointerOrRef ptr_or_ref)
{
    const clang::Type * clang_type = cppType->cppType();
    Type* target_type;
    if( ptr_or_ref == dlang::PointerType::POINTER )
    {
        const clang::PointerType * ptr_type = clang_type->castAs<clang::PointerType>();
        target_type = Type::get(ptr_type->getPointeeType());
    }
    else if( ptr_or_ref == dlang::PointerType::REFERENCE )
    {
        const clang::ReferenceType * ref_type = clang_type->castAs<clang::ReferenceType>();
        target_type = Type::get(ref_type->getPointeeType());
    }
    else
    {
        throw 21;
    }
    // If a strategy is already picked, then this returns immediately
    determineStrategy(target_type);
    bool target_is_reference_type = false;
    switch(target_type->getStrategy())
    {
        case UNKNOWN:
            throw 18;
        case REPLACE:
        case STRUCT:
            target_is_reference_type = false;
            break;
        case INTERFACE:
        case CLASS:
        case OPAQUE_CLASS:
            target_is_reference_type = true;
            break;
        default:
            throw 22;
    }

    std::shared_ptr<dlang::Type> result;
    if( target_is_reference_type )
    {
        result = translateType(target_type);
    }
    else
    {
        std::shared_ptr<dlang::Type> translated_pointee_type = translateType(target_type);
        result = std::shared_ptr<dlang::Type>(
                new dlang::PointerType(
                    translated_pointee_type, ptr_or_ref
                ));
    }

    return result;
}

std::shared_ptr<dlang::Type> replacePointer(Type* cppType)
{
    return replacePointerOrReference(cppType, dlang::PointerType::POINTER);
}
std::shared_ptr<dlang::Type> replaceReference(Type* cppType)
{
    return replacePointerOrReference(cppType, dlang::PointerType::REFERENCE);
}

std::shared_ptr<dlang::Type> replaceTypedef(Type* cppType)
{
    const clang::TypedefType * clang_type = cppType->cppType()->getAs<clang::TypedefType>();
    clang::TypedefNameDecl * clang_decl = clang_type->getDecl();

    auto all_declarations = DeclVisitor::getDeclarations();
    auto this_declaration = all_declarations.find(static_cast<clang::Decl*>(clang_decl));
    if( this_declaration == all_declarations.end() )
    {
        clang_decl->dump();
        throw std::runtime_error("Found a declaration that I'm not wrapping.");
    }

    TypedefDeclaration* cppDecl
        = dynamic_cast<TypedefDeclaration*>(this_declaration->second);
    auto search_result = translated.find(cppDecl);
    std::shared_ptr<dlang::Type> result;
    if( search_result == translated.end() )
    {
        TranslatorVisitor visitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = std::static_pointer_cast<dlang::Type>(visitor.translateTypedef(*cppDecl));
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = std::dynamic_pointer_cast<dlang::Type>(search_result->second);
    }

    return result;
}
// FIXME There's a way to generalize this and combine it with replaceTypedef,
// but I don't see it upon cursory inspection, so I'll get to it later.
std::shared_ptr<dlang::Type> replaceEnum(Type* cppType)
{
    const clang::EnumType * clang_type = cppType->cppType()->castAs<clang::EnumType>();
    clang::EnumDecl * clang_decl = clang_type->getDecl();

    auto all_declarations = DeclVisitor::getDeclarations();
    EnumDeclaration* cppDecl
        = dynamic_cast<EnumDeclaration*>(
                all_declarations.find(static_cast<clang::Decl*>(clang_decl))->second);
    auto search_result = translated.find(cppDecl);
    std::shared_ptr<dlang::Type> result;
    if( search_result == translated.end() )
    {
        TranslatorVisitor visitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = std::static_pointer_cast<dlang::Type>(visitor.translateEnum(*cppDecl));
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = std::dynamic_pointer_cast<dlang::Type>(search_result->second);
    }

    return result;
}

std::shared_ptr<dlang::Type> replaceFunction(Type*)
{
    // Needed for translating function types, but not declarations,
    // so I'm putting it off until later
    throw std::logic_error("Translation of function types is not implemented yet.");
}

// FIXME There's a way to generalize this and combine it with replaceTypedef,
// but I don't see it upon cursory inspection, so I'll get to it later.
std::shared_ptr<dlang::Type> replaceUnion(Type* cppType)
{
    const clang::RecordType * clang_type = cppType->cppType()->castAs<clang::RecordType>();
    clang::RecordDecl * clang_decl = clang_type->getDecl();

    auto all_declarations = DeclVisitor::getDeclarations();
    UnionDeclaration* cppDecl
        = dynamic_cast<UnionDeclaration*>(
                all_declarations.find(static_cast<clang::Decl*>(clang_decl))->second);
    auto search_result = translated.find(cppDecl);
    std::shared_ptr<dlang::Type> result;
    if( search_result == translated.end() )
    {
        TranslatorVisitor visitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = std::static_pointer_cast<dlang::Type>(visitor.translateUnion(*cppDecl));
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = std::dynamic_pointer_cast<dlang::Type>(search_result->second);
    }

    return result;
}

// TODO combine with replaceEnum and replaceTypedef?
static std::shared_ptr<dlang::Type> generateStruct(Type* cppType)
{
    if( cppType->getKind() != Type::Record )
    {
        throw std::logic_error("Attempted to generate a struct from a non-record type.");
    }
    const clang::RecordType * clang_type = cppType->cppType()->castAs<clang::RecordType>();
    clang::RecordDecl * clang_decl = clang_type->getDecl();

    auto& all_declarations = DeclVisitor::getDeclarations();
    RecordDeclaration* cppDecl
        = dynamic_cast<RecordDeclaration*>(
                all_declarations.find(static_cast<clang::Decl*>(clang_decl))->second);

    auto search_result = translated.find(cppDecl);
    std::shared_ptr<dlang::Type> result;
    if( search_result == translated.end() )
    {
        TranslatorVisitor visitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = std::static_pointer_cast<dlang::Type>(visitor.buildStruct(*cppDecl));
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = std::dynamic_pointer_cast<dlang::Type>(search_result->second);
    }

    return result;
}
static std::shared_ptr<dlang::Type> generateInterface(Type* cppType)
{
    if( cppType->getKind() != Type::Record )
    {
        throw std::logic_error("Attempted to generate an interface from a non-record type.");
    }
    const clang::RecordType * clang_type = cppType->cppType()->castAs<clang::RecordType>();
    clang::RecordDecl * clang_decl = clang_type->getDecl();

    auto& all_declarations = DeclVisitor::getDeclarations();
    RecordDeclaration* cppDecl
        = dynamic_cast<RecordDeclaration*>(
                all_declarations.find(static_cast<clang::Decl*>(clang_decl))->second);

    auto search_result = translated.find(cppDecl);
    std::shared_ptr<dlang::Type> result;
    if( search_result == translated.end() )
    {
        TranslatorVisitor visitor("", "");
        // translateTypedef does not try to place the declaration into a
        // module or context, so this is OK to do here.  It either:
        //  a) was already placed into the right spot
        //  b) will get placed later, when we visit the declaration
        result = std::static_pointer_cast<dlang::Type>(visitor.buildInterface(*cppDecl));
    }
    else
    {
        // This cast will succeed (unless something is wrong)
        // becuase search_result->second is really a TypeAlias, which is a Type.
        // We're going down and then up the type hierarchy.
        result = std::dynamic_pointer_cast<dlang::Type>(search_result->second);
    }

    return result;
}

std::shared_ptr<dlang::Type> translateType(Type* cppType)
{
    auto search_result = translated_types.find(cppType);
    if( search_result != translated_types.end() )
    {
        return search_result->second;
    }

    std::shared_ptr<dlang::Type> result;
    switch( cppType->getStrategy() )
    {
        case UNKNOWN:
            determineStrategy(cppType);
            result = translateType(cppType);
            break;
        case REPLACE:
            result = replaceType(cppType);
            break;
        case STRUCT:
            result = generateStruct(cppType);
            break;
        case INTERFACE:
            result = generateInterface(cppType);
            break;
        case CLASS:
            break;
        case OPAQUE_CLASS:
            break;
    }

    if( result )
    {
        translated_types.insert(std::make_pair(cppType, result));
    }
    else
    {
        throw std::runtime_error(std::string("Cannot translate type with strategy ") + std::to_string(cppType->getStrategy()));
    }
    return result;
}
