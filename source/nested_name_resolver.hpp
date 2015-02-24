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

#ifndef __NESTED_NAME_RESOLVER_HPP__
#define __NESTED_NAME_RESOLVER_HPP__

#include <clang/AST/DataRecursiveASTVisitor.h>

template<class Inner>
class NestedNameResolver : public clang::RecursiveASTVisitor<NestedNameResolver<Inner>>
{
    public:
    decltype(Inner::result) result;
    const clang::IdentifierInfo* identifier;
    llvm::ArrayRef<clang::TemplateArgument> template_args;
    NestedNameResolver(const clang::IdentifierInfo* id)
        : result(nullptr), identifier(id), template_args()
    { }

    // WalkUpFrom*Type is used to find the Decl for that type
    // Whenever we return from one of the WalkUpMethods, we either succeeded
    // or failed, so the traversal is done (return false)
    bool WalkUpFromType(clang::Type*)
    {
        throw std::logic_error("Don't know how to resolve dependent names in this type");
    }

    bool WalkUpFromRecordType(clang::RecordType* type)
    {
        return this->TraverseDecl(type->getDecl());
    }

    bool WalkUpFromTypedefType(clang::TypedefType* type)
    {
        return this->TraverseType(type->desugar());
    }

    bool WalkUpFromTemplateSpecializationType(clang::TemplateSpecializationType* type)
    {
        // FIXME I am not doing argument substitution or finding the right
        // specialization here
        clang::TemplateName template_name = type->getTemplateName();
        template_args = llvm::ArrayRef<clang::TemplateArgument>(type->getArgs(), type->getNumArgs());
        return this->TraverseDecl(template_name.getAsTemplateDecl());
    }

    // WalkUpFrom*Decl is used to get the final dependent Type from that Decl
    bool WalkUpFromDecl(clang::Decl*)
    {
        throw std::logic_error("Don't know how to resolve a dependent type name from this decl");
    }

    bool WalkUpFromClassTemplateDecl(clang::ClassTemplateDecl* decl)
    {
        if (template_args.data())
        {
            void* insertPos = nullptr;
            clang::ClassTemplateSpecializationDecl* specialization =
                decl->findSpecialization(template_args, insertPos);
            if (specialization)
            {
                return this->TraverseDecl(specialization);
            }
            else
            {
                // If we cannot find the specialization declaration, that means
                // that the template was not instantiated with these arguments
                // anywhere, so the arguments are unsubstituted template
                // parameters.  Right?
                // TODO partial specializations, and a more rigorous check
                return this->TraverseDecl(decl->getTemplatedDecl());
            }
        }
        else
        {
            return this->TraverseDecl(decl->getTemplatedDecl());
        }
    }

    bool lookupInContext(clang::DeclContext* ctx)
    {
        clang::DeclContextLookupResult lookup_result = ctx->lookup(identifier);
        if (lookup_result.size() == 0)
        {
            return false;
        }
        else if (lookup_result.size() > 1)
        {
            throw std::logic_error("Did not find exactly one result looking up a dependent type");
        }

        // This basically does the "check if a type declaration, then get type"
        Inner inner;
        inner.TraverseDecl(lookup_result[0]);
        result = inner.result;
        return true;
    }

    bool WalkUpFromRecordDecl(clang::RecordDecl* decl)
    {
        lookupInContext(decl);
        return false;
    }

    bool WalkUpFromCXXRecordDecl(clang::CXXRecordDecl* decl)
    {
        if (lookupInContext(decl) && !result)
        {
            // This means we found the clang decl but couldn't translate it
            // So just make a thing with the right name and hope it works
            clang::DeclContextLookupResult lookup_result = decl->lookup(identifier);
            lookup_result[0]->dump();
            Inner inner;
            inner.TraverseDecl(lookup_result[0]);
            throw std::logic_error("Couldn't translate the dependent type");
        }
        if (!result)
        {
            // TODO This is not quite following the C++ name resolution rules,
            // because I'm probably looking at private members in superclasses,
            // especially in the wrong order.
            for (clang::CXXRecordDecl::base_class_iterator iter = decl->bases_begin(),
                    finish = decl->bases_end();
                 iter != finish;
                 ++iter)
            {
                this->TraverseType(iter->getType());
                if (result)
                {
                    break;
                }
            }
        }
        return false;
    }
};

#endif // __NESTED_NAME_RESOLVER_HPP_
