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

module translate.expr;

import std.conv : to;
import std.experimental.logger;

static import std.d.ast;
import std.d.lexer : Token, tok;

static import unknown;

import translate.types;
import translate.decls;

private class ExpressionTranslator : unknown.ExpressionVisitor
{
    public:
    std.d.ast.ExpressionNode result;

    extern(C++) override
    void visit(unknown.BoolLiteralExpression expr)
    {
        auto primary = new std.d.ast.PrimaryExpression();
        primary.primary = Token(tok!"longLiteral", to!string(expr.getValue()), 0, 0, 0);
        result = primary;
    }

    extern(C++) override
    void visit(unknown.IntegerLiteralExpression expr)
    {
        auto primary = new std.d.ast.PrimaryExpression();
        primary.primary = Token(tok!"longLiteral", to!string(expr.getValue()), 0, 0, 0);
        result = primary;
    }

    extern(C++) override
    void visit(unknown.DeclaredExpression expr)
    {
        unknown.Declaration decl = expr.getDeclaration();
        if (auto deferred_ptr = cast(void*)decl in exprForDecl)
        {
            result = deferred_ptr.getExpression();
        }
        else
        {
            auto deferred = new DeferredExpression(null);
            exprForDecl[cast(void*)decl] = deferred;
            result = deferred.getExpression();
        }
    }

    extern(C++) override
    void visit(unknown.DelayedExpression expr)
    {
        unknown.Declaration decl = expr.getDeclaration();
        if (auto deferred_ptr = cast(void*)decl in exprForDecl)
        {
            result = deferred_ptr.getExpression();
        }
        else
        {
            auto deferred = new DeferredExpression(null);
            info("Created deferred expression ", cast(void*)deferred);
            info("For declaration ", cast(void*)decl);
            exprForDecl[cast(void*)decl] = deferred;
            result = deferred.getExpression();
        }
    }

    extern(C++) override
    void visit(unknown.CastExpression expr)
    {
        auto unaryResult = new std.d.ast.UnaryExpression();
        unaryResult.castExpression = new std.d.ast.CastExpression();
        unaryResult.castExpression.type = translateType(expr.getType(), QualifierSet.init);
        unaryResult.castExpression.unaryExpression = new std.d.ast.UnaryExpression();
        unaryResult.castExpression.unaryExpression.primaryExpression = new std.d.ast.PrimaryExpression();
        unaryResult.castExpression.unaryExpression.primaryExpression.expression = new std.d.ast.Expression();

        auto visitor = new ExpressionTranslator();
        expr.getSubExpression().visit(visitor);
        unaryResult.castExpression.unaryExpression.primaryExpression.expression.items = [visitor.result];
        result = unaryResult;
    }

    extern(C++) override
    void visit(unknown.UnwrappableExpression expr)
    {
    }
}

std.d.ast.ExpressionNode translateExpression(unknown.Expression expr)
{
    auto visitor = new ExpressionTranslator();
    expr.visit(visitor);
    return visitor.result;
}

class DeferredExpression : Resolvable
{
    public DeferredSymbolConcatenation symbol;
    protected:
    std.d.ast.UnaryExpression result;
    bool resolved;

    public:
    this(DeferredSymbolConcatenation sym)
    {
        symbol = sym;
        resolved = false;
        result = new std.d.ast.UnaryExpression();
    }

    override void resolve()
    {
        if (resolved) return;

        info("Resolving deferred expression ", cast(void*)this);
        symbol.resolve();
        std.d.ast.IdentifierOrTemplateInstance[] chain = symbol.getChain();

        if (chain.length > 1)
        {
            std.d.ast.UnaryExpression current = result;

            current.identifierOrTemplateInstance = chain[$-1];
            for(; chain.length > 1; chain = chain[0 .. $-2])
            {
                current.unaryExpression = new std.d.ast.UnaryExpression();
                current = current.unaryExpression;
            }

            current.primaryExpression = new std.d.ast.PrimaryExpression();
            current.primaryExpression.identifierOrTemplateInstance = chain[0];
        }
        else
        {
            auto primary = new std.d.ast.PrimaryExpression();
            primary.identifierOrTemplateInstance = chain[0];
            result.primaryExpression = primary;
        }

        resolved = true;
    }

    std.d.ast.ExpressionNode getExpression()
    {
        return result;
    }

    override std.d.ast.IdentifierOrTemplateInstance[] getChain()
    in {
        assert(resolved);
    }
    body {
        return symbol.getChain();
    }
}
