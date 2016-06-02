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

BoolLiteralExpression::BoolLiteralExpression(const clang::CXXBoolLiteralExpr* e)
    : value(e)
{ }

void BoolLiteralExpression::visit(ExpressionVisitor& visitor)
{
    visitor.visit(*this);
}

void BoolLiteralExpression::dump() const
{
    value->dump();
}

bool BoolLiteralExpression::getValue() const
{
    return value->getValue();
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

CastExpression::CastExpression(clang::CastExpr* e)
    : expr(e)
{ }

void CastExpression::dump() const
{
    expr->dump();
}

void CastExpression::visit(ExpressionVisitor& visitor)
{
    visitor.visit(*this);
}

Type* CastExpression::getType()
{
    return Type::get(expr->getType());
}

Expression * CastExpression::getSubExpression()
{
    return wrapClangExpression(expr->getSubExpr());
}

ParenExpression::ParenExpression(clang::ParenExpr* e)
    : expr(e)
{ }

void ParenExpression::dump() const
{
    expr->dump();
}

void ParenExpression::visit(ExpressionVisitor& visitor)
{
    visitor.visit(*this);
}

Type* ParenExpression::getType()
{
    return Type::get(expr->getType());
}

Expression * ParenExpression::getSubExpression()
{
    return wrapClangExpression(expr->getSubExpr());
}

void BinaryExpression::visit(ExpressionVisitor& visitor)
{
    visitor.visit(*this);
}

TwoSidedBinaryExpression::TwoSidedBinaryExpression(clang::BinaryOperator* e)
    : expr(e)
{ }

void TwoSidedBinaryExpression::dump() const
{
    expr->dump();
}

binder::string* TwoSidedBinaryExpression::getOperator()
{
    clang::BinaryOperator::Opcode op = expr->getOpcode();
    switch (op)
    {
        case clang::BO_Add:
            return new binder::string("+");
        case clang::BO_Div:
            return new binder::string("/");
        case clang::BO_Mul:
            return new binder::string("*");
        case clang::BO_Sub:
            return new binder::string("-");
        case clang::BO_Rem:
            return new binder::string("%");
        case clang::BO_LT:
            return new binder::string("<");
        case clang::BO_GT:
            return new binder::string(">");
        case clang::BO_LE:
            return new binder::string("<=");
        case clang::BO_GE:
            return new binder::string(">=");
        case clang::BO_EQ:
            return new binder::string("==");
        case clang::BO_NE:
            return new binder::string("!=");
        case clang::BO_LAnd:
            return new binder::string("&&");
        case clang::BO_LOr:
            return new binder::string("||");
        // Bitwise operators
        case clang::BO_And:
            return new binder::string("&");
        // TODO the rest of these.  There are a lot.
        default:
            this->dump();
            assert(0);
    }
}

Expression* TwoSidedBinaryExpression::getLeftExpression()
{
    return wrapClangExpression(expr->getLHS());
}
Expression* TwoSidedBinaryExpression::getRightExpression()
{
    return wrapClangExpression(expr->getRHS());
}

ExplicitOperatorBinaryExpression::ExplicitOperatorBinaryExpression(clang::CXXOperatorCallExpr* e)
    : expr(e)
{
    if (expr->getNumArgs() != 2)
    {
        expr->dump();
        throw std::logic_error("Can only handle CXXOperatorCallExpr with 2 arguments.");
    }
}

void ExplicitOperatorBinaryExpression::dump() const
{
    expr->dump();
}

binder::string* ExplicitOperatorBinaryExpression::getOperator()
{
    clang::OverloadedOperatorKind op = expr->getOperator();
    switch(op)
    {
        case clang::OO_Less:
            return new binder::string("<");
        case clang::OO_Greater:
            return new binder::string(">");
        case clang::OO_GreaterEqual:
            return new binder::string(">=");
        case clang::OO_Plus:
            return new binder::string("+");
        case clang::OO_Minus:
            return new binder::string("-");
        case clang::OO_EqualEqual:
            return new binder::string("==");
        case clang::OO_Exclaim:
            throw std::logic_error("Created a binary operator expression object for a unary operator.");
        default:
            this->dump();
            assert(0);
    }
}

Expression* ExplicitOperatorBinaryExpression::getLeftExpression()
{
    return wrapClangExpression(expr->getArg(0));
}
Expression* ExplicitOperatorBinaryExpression::getRightExpression()
{
    return wrapClangExpression(expr->getArg(1));
}

void UnaryExpression::visit(ExpressionVisitor& visitor)
{
    visitor.visit(*this);
}

ExplicitOperatorUnaryExpression::ExplicitOperatorUnaryExpression(clang::CXXOperatorCallExpr* e)
    : expr(e)
{
    if (expr->getNumArgs() != 1)
    {
        expr->dump();
        throw std::logic_error("Can only handle CXXOperatorCallExpr with 1 argument.");
    }
}

void ExplicitOperatorUnaryExpression::dump() const
{
    expr->dump();
}

binder::string* ExplicitOperatorUnaryExpression::getOperator()
{
    clang::OverloadedOperatorKind op = expr->getOperator();
    switch(op)
    {
        case clang::OO_Exclaim:
            assert(0);
        case clang::OO_GreaterEqual:
            throw std::logic_error("Created a unary operator expression object for a binary operator.");
        default:
            this->dump();
            assert(0);
    }
}

Expression* ExplicitOperatorUnaryExpression::getSubExpression()
{
    return wrapClangExpression(expr->getArg(0));
}

OneSidedUnaryExpression::OneSidedUnaryExpression(clang::UnaryOperator* e)
    : expr(e)
{ }

void OneSidedUnaryExpression::dump() const
{
    expr->dump();
}

binder::string* OneSidedUnaryExpression::getOperator()
{
    clang::UnaryOperator::Opcode op = expr->getOpcode();
    switch(op)
    {
        case clang::UO_LNot:
            return new binder::string("!");
        default:
            this->dump();
            assert(0);
    }
}

Expression* OneSidedUnaryExpression::getSubExpression()
{
    return wrapClangExpression(expr->getSubExpr());
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

    bool WalkUpFromCXXBoolLiteralExpr(clang::CXXBoolLiteralExpr* expr)
    {
        result = new BoolLiteralExpression(expr);
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

    bool WalkUpFromCastExpr(clang::CastExpr* expr)
    {
        result = new CastExpression(expr);

        return false;
    }

    bool WalkUpFromParenExpr(clang::ParenExpr* expr)
    {
        result = new ParenExpression(expr);

        return false;
    }

    bool WalkUpFromSubstNonTypeTemplateParmExpr(clang::SubstNonTypeTemplateParmExpr* expr)
    {
        // This is used in a template specialization where we have selected a
        // particular value for the template parameter.  So just use the
        // particular value.
        return wrapClangExpression(expr->getReplacement());
    }

    bool WalkUpFromBinaryOperator(clang::BinaryOperator* expr)
    {
        result = new TwoSidedBinaryExpression(expr);
        return false;
    }

    bool WalkUpFromCXXOperatorCallExpr(clang::CXXOperatorCallExpr* expr)
    {
        if (expr->getNumArgs() == 1)
        {
            result = new ExplicitOperatorUnaryExpression(expr);
        }
        else if (expr->getNumArgs() == 2)
        {
            result = new ExplicitOperatorBinaryExpression(expr);
        }
        return false;
    }

    bool WalkUpFromUnaryOperator(clang::UnaryOperator* expr)
    {
        result = new OneSidedUnaryExpression(expr);
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
