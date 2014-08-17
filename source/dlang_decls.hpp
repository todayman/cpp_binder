#ifndef __DLANG_DECLS_HPP__
#define __DLANG_DECLS_HPP__

#include <algorithm>
#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

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
        std::weak_ptr<Package> packageForName(const std::string& path)
        {
            return findForName<Package>(begin(path), end(path));
        }

        std::weak_ptr<Module> moduleForName(const std::string& path)
        {
            return findForName<Module>(begin(path), end(path));
        }
    };

    class Struct : public Declaration, public Type, public DeclarationContainer
    {
    };

    class Class : public Declaration
    {
        std::vector<std::shared_ptr<Declaration>> members;
    };

    class Interface : public Declaration
    {
        std::vector<std::shared_ptr<Declaration>> functions;
    };

    class Variable : public Declaration
    {
        std::shared_ptr<Type> type;
    };

    class Function : public Declaration
    {
        public:
        std::shared_ptr<Type> return_type;
        struct Parameter {
            std::string name;
            std::shared_ptr<Type> type;
        };
        std::vector<Parameter> arguments;
    };

    extern std::shared_ptr<Package> rootPackage;
} // namespace dlang

#endif // __DLANG_DECLS_HPP__
