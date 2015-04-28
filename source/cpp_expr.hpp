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

#ifndef __CPP_EXPR_HPP__
#define __CPP_EXPR_HPP__

namespace clang
{
    class CastExpr;
    class CXXBoolLiteralExpr;
    class DeclRefExpr;
    class Expr;
    class IntegerLiteral;
    class DependentScopeDeclRefExpr;
}

class BoolLiteralExpression;
class CastExpression;
class Declaration;
class DeclaredExpression;
class DelayedExpression;
class Expression;
class ExpressionVisitor;
class IntegerLiteralExpression;
class Type;
class UnwrappableExpression;

class ExpressionVisitor
{
    public:
    virtual void visit(BoolLiteralExpression& expr) = 0;
    virtual void visit(CastExpression& expr) = 0;
    virtual void visit(DeclaredExpression& expr) = 0;
    virtual void visit(DelayedExpression& expr) = 0;
    virtual void visit(IntegerLiteralExpression& expr) = 0;
    virtual void visit(UnwrappableExpression& expr) = 0;
};

class Expression
{
    public:
    virtual void dump() const = 0;
    virtual void visit(ExpressionVisitor& visitor) = 0;
};

class IntegerLiteralExpression : public Expression
{
    const clang::IntegerLiteral* value;

    public:
    explicit IntegerLiteralExpression(const clang::IntegerLiteral* expr)
        : value(expr)
    { }

    virtual void dump() const override;

    virtual void visit(ExpressionVisitor& visitor) override
    {
        visitor.visit(*this);
    }

    long long getValue() const;
};

class BoolLiteralExpression : public Expression
{
    const clang::CXXBoolLiteralExpr* value;

    public:
    explicit BoolLiteralExpression(const clang::CXXBoolLiteralExpr* expr);

    virtual void dump() const override;

    virtual void visit(ExpressionVisitor& visitor) override;

    bool getValue() const;
};

// A piece of an expression that was declared somewhere,
// e.g. a variable, a constant, etc.
class DeclaredExpression : public Expression
{
    const clang::DeclRefExpr* expr;

    public:
    explicit DeclaredExpression(const clang::DeclRefExpr* e)
        : expr(e)
    { }

    virtual void dump() const override;

    virtual void visit(ExpressionVisitor& visitor) override
    {
        visitor.visit(*this);
    }

    Declaration* getDeclaration() const;
};

class DelayedExpression : public Expression
{
    const clang::DependentScopeDeclRefExpr* expr;

    public:
    explicit DelayedExpression(const clang::DependentScopeDeclRefExpr* e)
        : expr(e)
    { }

    virtual void dump() const override;

    virtual void visit(ExpressionVisitor& visitor) override
    {
        visitor.visit(*this);
    }

    Declaration* getDeclaration() const;
};

class CastExpression : public Expression
{
    clang::CastExpr* expr;

    public:
    explicit CastExpression(clang::CastExpr* e);

    virtual void dump() const override;

    virtual void visit(ExpressionVisitor& visitor) override;

    Type* getType();

    Expression * getSubExpression();
};

class UnwrappableExpression : public Expression
{
    const clang::Expr* expr;
    public:
    UnwrappableExpression(const clang::Expr* e)
        : expr(e)
    { }

    virtual void dump() const override;
    virtual void visit(ExpressionVisitor& visitor) override
    {
        visitor.visit(*this);
    }
};

Expression* wrapClangExpression(clang::Expr* expr);

#endif // __CPP_EXPR_HPP__
