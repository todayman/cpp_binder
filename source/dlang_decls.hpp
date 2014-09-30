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
    };

    class DeclarationContainer;

    class Declaration
    {
        public:
        std::string name;
        DeclarationContainer * parent;
        Visibility visibility;
        virtual ~Declaration() { }

        virtual void visit(DeclarationVisitor& visitor) const = 0;
    };

    class DeclarationContainer
    {
        std::vector<std::shared_ptr<Declaration>> children;

        public:
        DeclarationContainer() = default;

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
        LANG_CPP
    };

    struct Linkage
    {
        Language lang;
        std::string name_space;
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
        std::string name;
        explicit StringType(std::string n)
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
        public:
        virtual ~FileDir() { }

        virtual void visit(PackageVisitor& visitor) const = 0;
    };

    class Module : public DeclarationContainer, public FileDir
    {
        std::string name;

        public:
        explicit Module(std::string n)
            : DeclarationContainer(), FileDir(), name(n)
        { }

        const std::string& getName() const
        {
            return name;
        }

        virtual void visit(PackageVisitor& visitor) const override
        {
            visitor.visitModule(*this);
        }
    };

    class Package : public FileDir
    {
        std::string name;
        std::unordered_map<std::string, std::shared_ptr<FileDir>> children;

        template<typename ConstIterator>
        decltype(children)::iterator findChild(ConstIterator start, ConstIterator finish, ConstIterator& end_of_first_element)
        {
            // Find the first dot.  If there is no dot, then this returns path.end(),
            // which is fine.
            end_of_first_element = std::find(start, finish, '.');

            if( end_of_first_element == start ) // Also catches the case when start == finish
            {
                throw 4;
            }

            return children.find(std::string(start, end_of_first_element));
        }
        public:
        Package() = default;
        explicit Package(std::string n)
            : name(n), children()
        { }

        const std::string& getName() const
        {
            return name;
        }

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
        std::weak_ptr<Result> findForName(const std::string& path)
        {
            return findForName<Result>(begin(path), end(path));
        }

        template<typename ConstIterator>
        std::shared_ptr<Module> getOrCreateModulePath(ConstIterator start, ConstIterator finish)
        {
            ConstIterator end_of_first_element;
            auto search_result = findChild(start, finish, end_of_first_element);
            if( search_result == children.end() )
            {
                std::string next_name(start, end_of_first_element);
                // Create
                if( end_of_first_element == finish )
                {
                    std::shared_ptr<Module> mod = std::make_shared<Module>(next_name);
                    std::shared_ptr<FileDir> result = std::static_pointer_cast<FileDir>(mod);
                    children.insert(std::make_pair(next_name, result));
                    return mod;
                }
                else {
                    std::shared_ptr<Package> package = std::make_shared<Package>(next_name);
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

        std::shared_ptr<Module> getOrCreateModulePath(const std::string& path)
        {
            return getOrCreateModulePath(begin(path), end(path));
        }
    };

    class Struct : public Declaration, public Type, public DeclarationContainer
    {
        public:
        virtual void visit(TypeVisitor& visitor) const override
        {
            visitor.visitStruct(*this);
        }
        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitStruct(*this);
        }
    };

    class Class : public Declaration
    {
        public:
        std::vector<std::shared_ptr<Declaration>> members;

        virtual void visit(DeclarationVisitor& visitor) const override
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

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitField(*this);
        }
    };

    class Interface : public Declaration
    {
        public:
        std::vector<std::shared_ptr<Declaration>> functions;

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitInterface(*this);
        }
    };

    class Variable : public Declaration
    {
        public:
        std::shared_ptr<Type> type;

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitVariable(*this);
        }
    };

    class Argument : public Declaration
    {
        public:
        std::shared_ptr<Type> type;

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

        virtual void visit(DeclarationVisitor& visitor) const override
        {
            visitor.visitFunction(*this);
        }
    };

    class TypeAlias : public Declaration, public Type
    {
        public:
        std::shared_ptr<Type> target_type;

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
