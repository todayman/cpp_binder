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

    class DeclarationContainer;

    class Declaration
    {
        public:
        std::string name;
        std::shared_ptr<DeclarationContainer> parent;
        Visibility visibility;
        virtual ~Declaration() { }
    };

    class DeclarationContainer
    {
        std::vector<std::shared_ptr<Declaration>> children;

        public:
        DeclarationContainer() = default;

        void insert(std::shared_ptr<Declaration> decl)
        {
            children.push_back(decl);
        }
    };

    // Needs to be separate from declarations for builtins like int that don't have declarations
    class Type
    {
    };

    // Need a superclass for Module and Package to use Composite pattern
    class FileDir
    {
        public:
        virtual ~FileDir() { }
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
            std::string name(start, finish);
            if( search_result == children.end() )
            {
                // Create
                if( end_of_first_element == finish )
                {
                    std::shared_ptr<Module> mod = std::make_shared<Module>(name);
                    std::shared_ptr<FileDir> result = std::static_pointer_cast<FileDir>(mod);
                    children.insert(std::make_pair(name, result));
                    return mod;
                }
                else {
                    std::shared_ptr<Package> package = std::make_shared<Package>(name);
                    std::shared_ptr<FileDir> result = std::static_pointer_cast<FileDir>(package);
                    children.insert(std::make_pair(name, result));
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
                std::shared_ptr<Package> package = std::make_shared<Package>(name);
                std::shared_ptr<FileDir> result = std::static_pointer_cast<FileDir>(package);
                children.insert(std::make_pair(name, result));
                return package->getOrCreateModulePath(end_of_first_element + 1, finish);
            }
        }

        std::shared_ptr<Module> getOrCreateModulePath(const std::string& path)
        {
            return getOrCreateModulePath(begin(path), end(path));
        }
    };

    class Struct : public Declaration, public Type, public DeclarationContainer
    {
    };

    class Class : public Declaration
    {
        public:
        std::vector<std::shared_ptr<Declaration>> members;
    };

    class Interface : public Declaration
    {
        public:
        std::vector<std::shared_ptr<Declaration>> functions;
    };

    class Variable : public Declaration
    {
        public:
        std::shared_ptr<Type> type;
    };

    class Argument : public Declaration
    {
        public:
        std::shared_ptr<Type> type;
    };

    class Function : public Declaration
    {
        public:
        std::shared_ptr<Type> return_type;
        std::vector<std::shared_ptr<Argument>> arguments;
    };

    class TypeAlias : public Declaration, public Type
    {
        public:
        std::shared_ptr<Type> target_type;
    };

    class EnumConstant : public Declaration
    {
        public:
        llvm::APSInt value;
    };

    class Enum : public Declaration, public Type
    {
        public:
        std::shared_ptr<Type> type;
        std::vector<std::shared_ptr<EnumConstant>> values;
    };

    extern std::shared_ptr<Package> rootPackage;
} // namespace dlang

void populateDAST();

#endif // __DLANG_DECLS_HPP__
