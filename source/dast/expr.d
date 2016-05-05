/*
 *  cpp_binder: an automatic C++ binding generator for D
 *  Copyright (C) 2015-2016 Paul O'Neil <redballoon36@gmail.com>
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

module dast.expr;

import std.conv : to;

static import dparse.ast;
import dparse.lexer : tok, Token;

import dast.common;
import dast.decls;
import dast.type;

interface Expression
{
    pure dparse.ast.ExpressionNode buildConcreteExpression() const;
}

class IntegerLiteralExpression : Expression
{
    long value;
    this(long v)
    {
        value = v;
    }

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new dparse.ast.PrimaryExpression();
        result.primary = tokenFromString(to!string(value));
        return result;
    }
}

class BoolLiteralExpression : Expression
{
    bool value;

    this(bool v)
    {
        value = v;
    }

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new dparse.ast.PrimaryExpression();
        result.primary = Token((value ? tok!"true" : tok!"false"), "", 0, 0, 0);
        return result;
    }
}

class CastExpression : Expression
{
    Type type;
    Expression argument;

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        assert(0);
    }
}

class ParenExpression : Expression
{
    Expression body_;

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        assert(body_ !is null); // in contract doesn't work b/c inheritance
        auto result = new dparse.ast.PrimaryExpression();
        auto expr = new dparse.ast.Expression();
        expr.items = [body_.buildConcreteExpression()];
        result.expression = expr;
        return result;
    }
}

class BinaryExpression : Expression
{
    string op;
    Expression lhs, rhs;

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        dparse.ast.ExpressionNode result;
        // TODO add a ton of parens to make sure that the precedence is right
        switch (op)
        {
            case "<":
                auto translation = new dparse.ast.RelExpression();
                translation.operator = tok!"<";
                translation.left = lhs.buildConcreteExpression();
                translation.right = rhs.buildConcreteExpression();
                result = translation;
                break;
            case ">":
                auto translation = new dparse.ast.RelExpression();
                translation.operator = tok!">";
                translation.left = lhs.buildConcreteExpression();
                translation.right = rhs.buildConcreteExpression();
                result = translation;
                break;
            default:
                assert(0);
        }

        return result;
    }
}

class UnaryExpression : Expression
{
    string op;
    Expression expr;

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        dparse.ast.ExpressionNode result;
        // TODO add a ton of parens to make sure that the precedence is right
        switch (op)
        {
            default:
                assert(0);
        }

        //return result;
    }
}

class DependentExpression : Expression
{
    Declaration parent;

    this(Declaration p)
    {
        parent = p;
    }

    override pure
    dparse.ast.ExpressionNode buildConcreteExpression() const
    {
        assert(0);
    }
}
