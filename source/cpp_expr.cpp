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

#include "cpp_expr.hpp"
#include "cpp_decl.hpp"
#include "nested_name_resolver.hpp"

#include "clang/AST/Expr.h"
#include "clang/AST/RecursiveASTVisitor.h"

void IntegerLiteralExpression::dump() const
{
    value->dump();
}

long long IntegerLiteralExpression::getValue() const
{
    return value->getValue().getSExtValue();
}

void DeclaredExpression::dump() const
{
    expr->dump();
}

Declaration* DeclaredExpression::getDeclaration() const
{
    return ::getDeclaration(expr->getDecl());
}

void DelayedExpression::dump() const
{
    expr->dump();
}

class InnerDeclResolver
{
    public:
    clang::Decl* result;

    bool TraverseDecl(clang::Decl* decl)
    {
        result = decl;
        return true;
    }
};

Declaration* DelayedExpression::getDeclaration() const
{
    clang::NestedNameSpecifier* container = expr->getQualifier();
    Declaration* result = nullptr;

    switch (container->getKind())
    {
        case clang::NestedNameSpecifier::Global:
            throw std::logic_error("Nested name kind is global");
            break;
        case clang::NestedNameSpecifier::Identifier:
        {
            /*clang::IdentifierInfo* id = container->getAsIdentifier();
            //NestedNameResolver<InnerDeclResolver> visitor(id);
            std::cerr << "id: " << id << "\n";
            std::cerr << "Token id: " << (int)id->getTokenID() << "\n";
            std::cerr << "token \"&&\" is " << (int)clang::tok::ampamp << "\n";
            std::cerr << "Name start: " << (void*)id->getNameStart() << "\n";
            std::cerr << "Name[0]: " << id->getNameStart()[0] << " (" << (int)id->getNameStart()[0] << ")\n";
            std::cerr << "Length is " << id->getLength() << "\n";
            std::cerr << "prefix is " << container->getPrefix() << "\n";
            std::cerr << "is dependent: " << container->isDependent() << "\n";
            std::cerr << "is instantiation dependent: " << container->isInstantiationDependent() << "\n";
            std::cerr << "unexpanded parameter pack: " << container->containsUnexpandedParameterPack() << "\n";
            std::cerr << "namespace: " << container->getAsNamespace() << "\n";
            std::cerr << "namespace alias: " << container->getAsNamespaceAlias() << "\n";
            std::cerr << "type: " << container->getAsType() << "\n";*/
            //throw std::logic_error("Nested name kind is identifier");
            return nullptr;
            break;
        }
        case clang::NestedNameSpecifier::TypeSpec:
        {
            const clang::Type* container_type = container->getAsType();
            NestedNameResolver<InnerDeclResolver> visitor(expr->getDeclName());
            visitor.TraverseType(clang::QualType(container_type, 0));
            if (visitor.result)
            {
                result = ::getDeclaration(visitor.result);
            }
            else
            {
                std::cerr << "Could not find result for ";
                container_type->dump();
                return nullptr;
            }
            break;
        }
        default:
            throw std::logic_error("Unknown nested name kind");
    }

    return result;
}

void UnwrappableExpression::dump() const
{
    expr->dump();
}

class ClangExpressionVisitor : public clang::RecursiveASTVisitor<ClangExpressionVisitor>
{
    Expression * result;
    public:
    ClangExpressionVisitor()
        : result(nullptr)
    { }

    // Overriding the traverse style methods because
    // each traversal should produce a single result -
    // the expression being traversed
    bool WalkUpFromIntegerLiteral(clang::IntegerLiteral* expr)
    {
        result = new IntegerLiteralExpression(expr);

        return false;
    }

    bool WalkUpFromDeclRefExpr(clang::DeclRefExpr* expr)
    {
        result = new DeclaredExpression(expr);

        return false;
    }

    bool WalkUpFromStmt(clang::Stmt* stmt)
    {
        stmt->dump();
        throw std::logic_error("ERROR: Unknown statement type");
    }

    bool WalkUpFromExpr(clang::Expr* expr)
    {
        result = new UnwrappableExpression(expr);

        return false;
    }

    bool WalkUpFromDependentScopeDeclRefExpr(clang::DependentScopeDeclRefExpr* expr)
    {
        result = new DelayedExpression(expr);

        return false;
    }

    Expression * getResult()
    {
        return result;
    }
};

Expression* wrapClangExpression(clang::Expr* expr)
{
    ClangExpressionVisitor visitor;
    visitor.TraverseStmt(expr);

    return visitor.getResult();
}
