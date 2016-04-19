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

static import std.d.ast;
import std.d.lexer : tok, Token;

import dast.common;
import dast.type;

interface Expression
{
    pure std.d.ast.ExpressionNode buildConcreteExpression() const;
}

class IntegerLiteralExpression : Expression
{
    long value;
    this(long v)
    {
        value = v;
    }

    override pure
    std.d.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new std.d.ast.PrimaryExpression();
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
    std.d.ast.ExpressionNode buildConcreteExpression() const
    {
        auto result = new std.d.ast.PrimaryExpression();
        result.primary = Token((value ? tok!"true" : tok!"false"), "", 0, 0, 0);
        return result;
    }
}

class CastExpression : Expression
{
    Type type;
    Expression argument;

    override pure
    std.d.ast.ExpressionNode buildConcreteExpression() const
    {
        assert(0);
    }
}
