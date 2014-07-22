#ifndef __CPP_DECL_HPP__
#define __CPP_DECL_HPP__

#include "clang/AST/Decl.h"
#include "clang/AST/RecursiveASTVisitor.h"

namespace cpp
{
    // Same thing as Type, but for declarations of functions,
    // classes, etc.
    class Declaration
    {
        // Attributes!
        // Pointer to D declaration!
        public:
        virtual const clang::Decl* decl() = 0;
        const std::string name() {
            return _name;
        }
        protected:
        std::string _name;

        void setName(std::string name) {
            _name = name;
        }

        friend class DeclVisitor;
    };

#define DECLARATION_CLASS_2(C, D) \
    class D##Declaration : public Declaration \
    { \
        private: \
        const clang::C##Decl* _decl; \
\
        public: \
        D##Declaration(const clang::C##Decl* d) \
            : _decl(d) \
        { } \
        virtual const clang::Decl* decl() override { \
            return _decl; \
        } \
    }
#define DECLARATION_CLASS(KIND) DECLARATION_CLASS_2(KIND, KIND)
DECLARATION_CLASS(Function);
DECLARATION_CLASS(Namespace);
DECLARATION_CLASS(Record);
DECLARATION_CLASS(Typedef);
DECLARATION_CLASS(Enum);
DECLARATION_CLASS(Field);
DECLARATION_CLASS(EnumConstant); // TODO change this to a generic constant class

DECLARATION_CLASS_2(Record, Union);
DECLARATION_CLASS_2(CXXMethod, Method);
DECLARATION_CLASS_2(CXXConstructor, Constructor);
DECLARATION_CLASS_2(CXXDestructor, Destructor);
DECLARATION_CLASS_2(ParmVar, Argument);
DECLARATION_CLASS_2(Var, Variable);

} // namespace cpp

#endif // __CPP_DECL_HPP__
