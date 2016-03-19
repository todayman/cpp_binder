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

static import unknown;

import translate.types;
import translate.decls;

import dast.expr;

private class ExpressionTranslator : unknown.ExpressionVisitor
{
    public:
    Expression result;

    extern(C++) override
    void visit(unknown.BoolLiteralExpression expr)
    {
        result = new BoolLiteralExpression(expr.getValue());
    }

    extern(C++) override
    void visit(unknown.IntegerLiteralExpression expr)
    {
        result = new IntegerLiteralExpression(expr.getValue());
    }

    extern(C++) override
    void visit(unknown.DeclaredExpression expr)
    {
        unknown.Declaration decl = expr.getDeclaration();
        result = startDeclExprBuild(decl);
    }

    extern(C++) override
    void visit(unknown.DelayedExpression expr)
    {
        unknown.Declaration decl = expr.getDeclaration();
        // TODO need to be careful here...
        /*if (auto deferred_ptr = cast(void*)decl in exprForDecl)
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
        }*/
        assert(0);
    }

    extern(C++) override
    void visit(unknown.CastExpression expr)
    {
        auto castExpression = new CastExpression();
        castExpression.type = translateType(expr.getType(), QualifierSet.init);

        auto visitor = new ExpressionTranslator();
        expr.getSubExpression().visit(visitor);
        castExpression.argument = visitor.result;
        result = castExpression;
    }

    extern(C++) override
    void visit(unknown.UnwrappableExpression expr)
    {
    }
}

Expression translateExpression(unknown.Expression expr)
{
    auto visitor = new ExpressionTranslator();
    expr.visit(visitor);
    if (visitor.result is null)
    {
        info("Failed to translate expression:");
        expr.dump();
        assert(0);
    }
    return visitor.result;
}
