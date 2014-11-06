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

#ifndef __DLANG_DECLS_HPP__
#define __DLANG_DECLS_HPP__

#include <algorithm>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

#include "llvm/ADT/APSInt.h"

#include "string.hpp"
using namespace binder;

class Declaration;

namespace dlang
{
    enum Visibility
    {
        PRIVATE,
        PACKAGE,
        PROTECTED,
        PUBLIC,
        EXPORT,
    };

    class Package;
    class Module;
    class Function;
    class Argument;
    class Variable;
    class Interface;
    class Struct;
    class Class;
    class TypeAlias;
    class EnumConstant;
    class Enum;
    class Field;
    class Method;
    class Union;

    class StringType;
    class PointerType;

    class PackageVisitor
    {
        public:
        virtual void visitPackage(const dlang::Package& package) = 0;
        virtual void visitModule(const dlang::Module& module) = 0;
    };
    class DeclarationVisitor
    {
        public:
        virtual void visitFunction(const Function&) = 0;
        virtual void visitArgument(const Argument&) = 0;
        virtual void visitVariable(const Variable&) = 0;
        virtual void visitInterface(const Interface&) = 0;
        virtual void visitStruct(const Struct&) = 0;
        virtual void visitClass(const Class&) = 0;
        virtual void visitTypeAlias(const TypeAlias&) = 0;
        virtual void visitEnum(const Enum&) = 0;
        virtual void visitEnumConstant(const EnumConstant&) = 0;
        virtual void visitField(const Field&) = 0;
        virtual void visitUnion(const Union&) = 0;
        virtual void visitMethod(const Method&) = 0;
    };
    class TypeVisitor
    {
        public:
        virtual void visitString(const StringType&) = 0;
        virtual void visitStruct(const Struct&) = 0;
        virtual void visitTypeAlias(const TypeAlias&) = 0;
        virtual void visitEnum(const Enum&) = 0;
        virtual void visitPointer(const PointerType&) = 0;
        virtual void visitUnion(const Union&) = 0;
        virtual void visitClass(const Class&) = 0;
        virtual void visitInterface(const Interface&) = 0;
    };

    class DeclarationContainer;

    class Declaration
    {
        public:
        string name;
        DeclarationContainer * parent;
        Visibility visibility;
        ::Declaration * derived_from;

        Declaration(::Declaration * df)
            : name(), parent(nullptr), visibility(PRIVATE), derived_from(df)
        { }
        virtual ~Declaration() { }

        virtual void visit(DeclarationVisitor& visitor) const = 0;
    };

    class DeclarationContainer
    {
        std::vector<std::shared_ptr<Declaration>> children;

        public:
        DeclarationContainer() = default;
        virtual ~DeclarationContainer() = default;

        void insert(std::shared_ptr<Declaration> decl)
        {
            children.push_back(decl);
            decl->parent = this;
        }

        const decltype(children)& getChildren() const
        {
            return children;
        }
    };

    enum Language
    {
        LANG_C,
        LANG_CPP,
        LANG_D
    };

    struct Linkage
    {
        Language lang;
        string name_space;
    };

    // Needs to be separate from declarations for builtins like int that don't have declarations
    class Type
    {
        public:
        virtual ~Type() = default;

        virtual void visit(TypeVisitor& visitor) const = 0;
    };

    class StringType : public Type
    {
        public:
        string name;

        explicit StringType(string n)
            : name(n)
        { }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitString(*this);
        }
    };

    class PointerType : public Type
    {
        public:
        enum PointerOrRef {
            POINTER,
            REFERENCE
        } pointer_vs_ref;
        std::shared_ptr<dlang::Type> target;
        /* An idea for how to handle classes:
        // True when the target of this pointer is a reference type, i.e. a class
        // Usages of this type then omit the (*) or (ref) indicator
        bool points_to_reference_type;
        */

        explicit PointerType(std::shared_ptr<dlang::Type> tgt, PointerOrRef p)
            : pointer_vs_ref(p), target(tgt)
        { }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitPointer(*this);
        }
    };

    // Need a superclass for Module and Package to use Composite pattern
    class FileDir
    {
        string name;
        Package* parent;

        public:
        FileDir(string n, Package * p)
            : name(n), parent(p)
        { }
        virtual ~FileDir() { }

        const string& getName() const
        {
            return name;
        }

        virtual Package* getParent() const
        {
            return parent;
        }

        virtual void visit(PackageVisitor& visitor) const = 0;
    };

    class Module : public DeclarationContainer, public FileDir
    {

        public:
        explicit Module(string n, Package * p)
            : DeclarationContainer(), FileDir(n, p)
        { }

        virtual void visit(PackageVisitor& visitor) const override
        {
            visitor.visitModule(*this);
        }
    };

    class Package : public FileDir
    {
        std::unordered_map<string, std::shared_ptr<FileDir>> children;

        template<typename ConstIterator>
        decltype(children)::iterator findChild(ConstIterator start, ConstIterator finish, ConstIterator& end_of_first_element)
        {
            // Find the first dot.  If there is no dot, then this returns path.end(),
            // which is fine.
            end_of_first_element = std::find(start, finish, '.');

            if( end_of_first_element == start ) // Also catches the case when start == finish
            {
                throw std::logic_error("Attempted to find the package / module with the empty name ("")");
            }

            return children.find(string(start, end_of_first_element));
        }
        public:
        Package() = default;
        explicit Package(string n, Package * p)
            : FileDir(n, p), children()
        { }

        const decltype(children)& getChildren() const
        {
            return children;
        }

        virtual void visit(PackageVisitor& visitor) const override
        {
            visitor.visitPackage(*this);
        }

        // These return weak pointers because every package is owned by its
        // parent, and the root package owns all the top level packages.
        // Not entirely sure that's the right choice, though.
        template<typename Result, typename ConstIterator>
        std::weak_ptr<Result> findForName(ConstIterator start, ConstIterator finish)
        {
            ConstIterator end_of_first_element;
            auto search_result = findChild(start, finish, end_of_first_element);
            if( search_result == children.end() )
            {
                return std::weak_ptr<Result>();
            }

            if( end_of_first_element != finish )
            {
                // This means that there are more letters after the dot,
                // so the current name is a package name, so recurse
                std::shared_ptr<Package> subpackage = std::dynamic_pointer_cast<Package>(search_result->second);
                if( subpackage )
                {
                    return subpackage->findForName<Result>(end_of_first_element + 1, finish);
                }
                else
                {
                    return std::weak_ptr<Result>();
                }
            }
            else
            {
                return std::weak_ptr<Result>(std::dynamic_pointer_cast<Result>(search_result->second));
            }
        }
        template<typename Result>
        std::weak_ptr<Result> findForName(const string& path)
        {
            return findForName<Result>(std::begin(path), std::end(path));
        }

        template<typename ConstIterator>
        std::shared_ptr<Module> getOrCreateModulePath(ConstIterator start, ConstIterator finish)
        {
            ConstIterator end_of_first_element;
            auto search_result = findChild(start, finish, end_of_first_element);
            if( search_result == children.end() )
            {
                string next_name(start, end_of_first_element);
                // Create
                if( end_of_first_element == finish )
                {
                    std::shared_ptr<Module> mod = std::make_shared<Module>(next_name, this);
                    std::shared_ptr<FileDir> result = std::static_pointer_cast<FileDir>(mod);
                    children.insert(std::make_pair(next_name, result));
                    return mod;
                }
                else {
                    std::shared_ptr<Package> package = std::make_shared<Package>(next_name, this);
                    std::shared_ptr<FileDir> result = std::static_pointer_cast<FileDir>(package);
                    children.insert(std::make_pair(next_name, result));
                    return package->getOrCreateModulePath(end_of_first_element + 1, finish);
                }
            }

            // Entry exists, and this is not the end of the path
            if( end_of_first_element != finish )
            {
                // This means that there are more letters after the dot,
                // so the current name is a package name, so recurse
                std::shared_ptr<Package> subpackage = std::dynamic_pointer_cast<Package>(search_result->second);
                if( subpackage )
                {
                    return subpackage->getOrCreateModulePath(end_of_first_element + 1, finish);
                }
                else
                {
                    // This is a module, but expected a package name
                    throw 13; // TODO
                }
            }
            else
            {
                // entry exists, and this is the end of the path
                std::shared_ptr<Module> module = std::dynamic_pointer_cast<Module>(search_result->second);
                if( !module )
                {
                    // This is a package, but expected a module
                    throw 13; // TODO
                }
                else
                {
                    return module;
                }
            }
        }

        std::shared_ptr<Module> getOrCreateModulePath(const string& path)
        {
            return getOrCreateModulePath(std::begin(path), std::end(path));
        }
    };

    // FIXME has some commonality with Function
    class Method : public Declaration
    {
        public:
        enum {
            VIRTUAL,
            STATIC,
            FINAL
        } kind;
        std::shared_ptr<Type> return_type;
        std::vector<std::shared_ptr<Argument>> arguments;

        Method(::Declaration * cpp)
            : Declaration(cpp), kind(VIRTUAL), return_type(), arguments()
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitMethod(*this);
        }
    };

    class Struct : public Declaration, public Type, public DeclarationContainer
    {
        public:
        Linkage linkage;
        std::shared_ptr<Struct> superclass;
        std::vector<std::shared_ptr<Method>> methods;

        Struct(::Declaration * cpp)
            : Declaration(cpp), linkage(), superclass(), methods()
        { }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitStruct(*this);
        }
        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitStruct(*this);
        }
    };

    class Class : public Declaration, public Type, public DeclarationContainer
    {
        public:
        Class(::Declaration * cpp)
            : Declaration(cpp)
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitClass(*this);
        }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitClass(*this);
        }
    };

    class Field : public Declaration
    {
        public:
        std::shared_ptr<Type> type;
        Visibility visibility;
        // const, immutable, etc.

        Field(::Declaration * cpp)
            : Declaration(cpp), type(), visibility()
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitField(*this);
        }
    };

    class Interface : public Declaration, public Type, public DeclarationContainer
    {
        public:
        Linkage linkage;
        std::vector<std::shared_ptr<Interface>> superclasses;
        std::vector<std::shared_ptr<Declaration>> methods;

        Interface(::Declaration * cpp)
            : Declaration(cpp), linkage(), superclasses(), methods()
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitInterface(*this);
        }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitInterface(*this);
        }
    };

    class Variable : public Declaration
    {
        public:
        Linkage linkage;
        std::shared_ptr<Type> type;

        Variable(::Declaration * cpp)
            : Declaration(cpp), linkage(), type()
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitVariable(*this);
        }
    };

    class Argument : public Declaration
    {
        public:
        std::shared_ptr<Type> type;

        Argument(::Declaration * cpp)
            : Declaration(cpp)
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitArgument(*this);
        }
    };

    class Function : public Declaration
    {
        public:
        std::shared_ptr<Type> return_type;
        std::vector<std::shared_ptr<Argument>> arguments;
        Linkage linkage;

        Function(::Declaration * cpp)
            : Declaration(cpp), return_type(), arguments(), linkage()
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitFunction(*this);
        }
    };

    class TypeAlias : public Declaration, public Type
    {
        public:
        std::shared_ptr<Type> target_type;

        TypeAlias(::Declaration * cpp)
            : Declaration(cpp), target_type()
        { }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitTypeAlias(*this);
        }
        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitTypeAlias(*this);
        }
    };

    class EnumConstant : public Declaration
    {
        public:
        llvm::APSInt value;

        EnumConstant(::Declaration * cpp)
            : Declaration(cpp), value()
        { }

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitEnumConstant(*this);
        }
    };

    class Enum : public Declaration, public Type
    {
        public:
        std::shared_ptr<Type> type;
        std::vector<std::shared_ptr<EnumConstant>> values;

        Enum(::Declaration * cpp)
            : Declaration(cpp), type(), values()
        { }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitEnum(*this);
        }
        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitEnum(*this);
        }
    };

    class Union : public Declaration, public Type, public DeclarationContainer
    {
        public:
        Union(::Declaration * cpp)
            : Declaration(cpp)
        { }

        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitUnion(*this);
        }
        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitUnion(*this);
        }
    };

    extern std::shared_ptr<Package> rootPackage;
} // namespace dlang

void populateDAST();

#endif // __DLANG_DECLS_HPP__
