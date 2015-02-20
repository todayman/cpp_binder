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
    class Expr;
    class DeclRefExpr;
    class IntegerLiteral;
}

class Declaration;
class Expression;
class ExpressionVisitor;
class IntegerLiteralExpression;
class DeclaredExpression;

class ExpressionVisitor
{
    public:
    virtual void visit(IntegerLiteralExpression& expr) = 0;
    virtual void visit(DeclaredExpression& expr) = 0;
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

    virtual void visit(ExpressionVisitor& visitor)
    {
        visitor.visit(*this);
    }

    long long getValue() const;
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

    virtual void visit(ExpressionVisitor& visitor)
    {
        visitor.visit(*this);
    }

    Declaration* getDeclaration() const;
};

Expression* wrapClangExpression(clang::Expr* expr);

#endif // __CPP_EXPR_HPP__
