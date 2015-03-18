module unknown;


import 
    manual_types, 
    binder;

extern (C++) interface DeclarationAttributes
{

    static public DeclarationAttributes make();

    final public void setBound(bool value);

    final public void setTargetModule(binder.string value);

    final public void setVisibility(Visibility value);

    final public void setRemovePrefix(binder.string value);
}

extern (C++) interface TypeAttributes
{

    static public TypeAttributes make();

    public Strategy getStrategy() const;

    public void setStrategy(Strategy s);

    public void setTargetName(binder.string new_target);

    public void setTargetModule(binder.string new_module);
}

extern (C++) void applyConfigToObject(const binder.string name, clang.ASTUnit* astunit, const DeclarationAttributes decl_attributes, const TypeAttributes type_attributes);

extern (C++) interface NotWrappableException : std.runtime_error {}

enum Strategy : uint 

{
UNKNOWN = 0,
REPLACE = 1,
STRUCT = 2,
INTERFACE = 3,
CLASS = 4,
OPAQUE_CLASS = 5
}

extern (C++) interface Type
{

    static public void printTypeNames();

    static public Type get(const(clang.Type)* type, const(clang.PrintingPolicy)* pp);

    static public Type get(const ref clang.QualType qType, const(clang.PrintingPolicy)* pp);

    final public Type.Kind getKind() const;

    final public void chooseReplaceStrategy(const binder.string replacement);

    final public void setStrategy(Strategy s);

    final public Strategy getStrategy() const;

    public bool isReferenceType() const;

    final public binder.string getReplacement() const;

    final public binder.string getReplacementModule() const;

    final public void setReplacementModule(binder.string mod);

    public Declaration getDeclaration() const;

    public void visit(TypeVisitor visitor);

    public void dump() const;

    final public void applyAttributes(const TypeAttributes attribs);

    public bool isWrappable(bool refAllowed);

    enum Kind : uint 

    {
Invalid = 0,
Builtin = 1,
Pointer = 2,
Reference = 3,
Record = 4,
Union = 5,
Array = 6,
Function = 7,
Typedef = 8,
Vector = 9,
Enum = 10,
Qualified = 11,
TemplateArgument = 12,
TemplateSpecialization = 13,
Delayed = 14
    }

    extern (C++) interface DontSetUnknown : std.runtime_error {}

    extern (C++) interface UseReplaceMethod : std.runtime_error {}

    extern (C++) interface WrongStrategy : std.runtime_error {}
}

extern (C++) interface TypeVisitor
{

    public void visit(InvalidType type);

    public void visit(BuiltinType type);

    public void visit(PointerType type);

    public void visit(ReferenceType type);

    public void visit(NonTemplateRecordType type);

    public void visit(TemplateRecordType type);

    public void visit(UnionType type);

    public void visit(ArrayType type);

    public void visit(FunctionType type);

    public void visit(TypedefType type);

    public void visit(VectorType type);

    public void visit(EnumType type);

    public void visit(QualifiedType type);

    public void visit(TemplateArgumentType type);

    public void visit(TemplateSpecializationType type);

    public void visit(DelayedType type);
}

extern (C++) interface InvalidType : Type {}

extern (C++) interface BuiltinType : Type {}

extern (C++) interface RecordType : Type
{

    public RecordDeclaration getRecordDeclaration() const;
}

extern (C++) interface NonTemplateRecordType : RecordType {}

extern (C++) interface TemplateRecordType : RecordType {}

extern (C++) interface PointerOrReferenceType : Type
{

    public Type getPointeeType() const;
}

extern (C++) interface PointerType : PointerOrReferenceType {}

extern (C++) interface ReferenceType : PointerOrReferenceType {}

extern (C++) interface TypedefType : Type
{

    final public TypedefDeclaration getTypedefDeclaration() const;

    final public Type getTargetType() const;
}

extern (C++) interface EnumType : Type
{

    final public EnumDeclaration getEnumDeclaration() const;
}

extern (C++) interface UnionType : Type
{

    final public UnionDeclaration getUnionDeclaration() const;
}

extern (C++) interface ArrayType : Type
{

    public bool isFixedLength();

    public bool isDependentLength();

    public long getLength();

    public Expression getLengthExpression();

    public Type getElementType() const;
}

extern (C++) interface ConstantArrayType : ArrayType {}

extern (C++) interface VariableArrayType : ArrayType {}

extern (C++) interface DependentLengthArrayType : ArrayType {}

extern (C++) interface ArgumentTypeRange
{

    public bool empty();

    public Type front();

    public void popFront();
}

extern (C++) interface FunctionType : Type
{

    public Type getReturnType();

    public ArgumentTypeRange getArgumentRange();
}

extern (C++) interface QualifiedType : Type
{

    final public Type unqualifiedType();

    final public const Type unqualifiedType() const;

    final public bool isConst() const;
}

extern (C++) interface VectorType : Type {}

extern (C++) interface TemplateArgumentType : Type
{

    final public TemplateTypeArgumentDeclaration getTemplateTypeArgumentDeclaration() const;

    final public void setTemplateList(clang.TemplateParameterList* tl);

    final public binder.string getIdentifier() const;
}

extern (C++) interface TemplateSpecializationType : Type
{

    final public Declaration getTemplateDeclaration() const;

    final public uint getTemplateArgumentCount() const;

    final public TemplateArgumentInstanceIterator getTemplateArgumentBegin() const;

    final public TemplateArgumentInstanceIterator getTemplateArgumentEnd() const;
}

extern (C++) interface NestedNameWrapper
{

    final public bool isType() const;

    final public bool isIdentifier() const;

    final public NestedNameWrapper getPrefix() const;

    final public binder.string getAsIdentifier() const;

    final public Type getAsType() const;
}

extern (C++) interface DelayedType : Type
{

    final public Type resolveType() const;

    final public binder.string getIdentifier() const;

    final public NestedNameWrapper getQualifier() const;
}

extern (C++) interface TemplateArgumentInstanceIterator
{

    public void advance();

    public bool equals(TemplateArgumentInstanceIterator other);

    public TemplateArgumentInstanceIterator.Kind getKind();

    public Type getType();

    public long getInteger();

    public Expression getExpression();

    public void dumpPackInfo();

    enum Kind : uint 

    {
Type = 0,
Integer = 1,
Expression = 2,
Pack = 3
    }
}

extern (C++) interface FatalTypeNotWrappable : NotWrappableException
{

    public const(clang.Type)* getType() const;
}

extern (C++) interface SkipUnwrappableType : NotWrappableException
{

    public const(clang.Type)* getType() const;
}

extern (C++) interface SkipRValueRef : SkipUnwrappableType
{

    public const(char)* what() const;
}

extern (C++) interface SkipTemplate : SkipUnwrappableType
{

    public const(char)* what() const;
}

extern (C++) interface SkipMemberPointer : SkipUnwrappableType
{

    public const(char)* what() const;
}

enum Visibility : uint 

{
UNSET = 0,
PRIVATE = 1,
PACKAGE = 2,
PROTECTED = 3,
PUBLIC = 4,
EXPORT = 5
}

extern (C++) Visibility accessSpecToVisibility(clang.AccessSpecifier as);

extern (C++) bool isCXXRecord(const(clang.Decl)* decl);

extern (C++) bool isTemplateTypeParmDecl(const(clang.Decl)* decl);

extern (C++) interface Declaration
{

    protected void setSourceName(binder.string name);

    protected void markUnwrappable();

    public clang.SourceLocation getSourceLocation() const;

    public binder.string getSourceName() const;

    public binder.string getTargetName() const;

    public bool isWrappable() const;

    public void shouldEmit(bool decision);

    public bool shouldEmit() const;

    public void setTargetModule(binder.string target);

    public bool isTargetModuleSet() const;

    public binder.string getTargetModule() const;

    public Visibility getVisibility() const;

    public void setVisibility(Visibility vis);

    public void removePrefix(binder.string prefix);

    public Type getType() const;

    public void visit(DeclarationVisitor visitor);

    public void dump();

    final public void applyAttributes(const DeclarationAttributes attribs);
}

extern (C++) void applyAttributesToDeclByName(const DeclarationAttributes attribs, const binder.string declName);

extern (C++) interface NotTypeDecl : std.runtime_error {}

extern (C++) interface DeclarationRange
{

    public bool empty();

    public Declaration front();

    public void popFront();
}

extern (C++) interface DeclarationVisitor
{

    public void visitFunction(FunctionDeclaration node);

    public void visitNamespace(NamespaceDeclaration node);

    public void visitRecord(RecordDeclaration node);

    public void visitRecordTemplate(RecordTemplateDeclaration node);

    public void visitTypedef(TypedefDeclaration node);

    public void visitEnum(EnumDeclaration node);

    public void visitField(FieldDeclaration node);

    public void visitEnumConstant(EnumConstantDeclaration node);

    public void visitUnion(UnionDeclaration node);

    public void visitSpecializedRecord(SpecializedRecordDeclaration node);

    public void visitMethod(MethodDeclaration node);

    public void visitConstructor(ConstructorDeclaration node);

    public void visitDestructor(DestructorDeclaration node);

    public void visitArgument(ArgumentDeclaration node);

    public void visitVariable(VariableDeclaration node);

    public void visitTemplateTypeArgument(TemplateTypeArgumentDeclaration node);

    public void visitTemplateNonTypeArgument(TemplateNonTypeArgumentDeclaration node);

    public void visitUnwrappable(UnwrappableDeclaration node);
}

extern (C++) interface ConstructorDeclaration : Declaration {}

extern (C++) interface DestructorDeclaration : Declaration {}

extern (C++) interface VariableDeclaration : Declaration
{

    public clang.LanguageLinkage getLinkLanguage() const;
}

extern (C++) interface ArgumentDeclaration : Declaration {}

extern (C++) interface NamespaceDeclaration : Declaration
{

    public DeclarationRange getChildren();
}

extern (C++) interface TypedefDeclaration : Declaration
{

    final public TypedefType getTypedefType() const;

    final public Type getTargetType() const;
}

extern (C++) interface EnumDeclaration : Declaration
{

    final public EnumType getEnumType() const;

    public Type getMemberType() const;

    public DeclarationRange getChildren();
}

extern (C++) interface EnumConstantDeclaration : Declaration
{

    public long getLLValue() const;
}

extern (C++) interface ArgumentIterator
{

    public ArgumentDeclaration get();

    public void advance();

    public bool equals(ArgumentIterator other);
}

extern (C++) interface FunctionDeclaration : Declaration
{

    public clang.LanguageLinkage getLinkLanguage() const;

    public Type getReturnType() const;

    public ArgumentIterator getArgumentBegin();

    public ArgumentIterator getArgumentEnd();

    public bool isOverloadedOperator() const;
}

extern (C++) interface FieldDeclaration : Declaration {}

extern (C++) interface OverriddenMethodIterator
{

    public MethodDeclaration get();

    public void advance();

    public bool equals(OverriddenMethodIterator other);
}

extern (C++) interface MethodDeclaration : Declaration
{

    public bool isConst() const;

    public bool isStatic() const;

    public bool isVirtual() const;

    public bool isOverloadedOperator() const;

    public Type getReturnType() const;

    public ArgumentIterator getArgumentBegin();

    public ArgumentIterator getArgumentEnd();

    public OverriddenMethodIterator getOverriddenBegin();

    public OverriddenMethodIterator getOverriddenEnd();
}

extern (C++) interface FieldRange
{

    public FieldDeclaration front();

    public void popFront();

    public bool empty() const;
}

extern (C++) interface MethodRange
{

    public bool empty();

    public MethodDeclaration front();

    public void popFront();
}

extern (C++) struct Superclass
{

    public bool isVirtual;

    public Visibility visibility;

    public Type base;
}

extern (C++) interface SuperclassIterator
{

    public Superclass* get();

    public void advance();

    public bool equals(SuperclassIterator other);
}

extern (C++) interface RecordDeclaration : Declaration
{

    final protected const(clang.RecordDecl)* definitionOrThis() const;

    final public RecordType getRecordType() const;

    public FieldRange getFieldRange() const;

    public DeclarationRange getChildren() const;

    public MethodRange getMethodRange();

    public SuperclassIterator getSuperclassBegin();

    public SuperclassIterator getSuperclassEnd();

    public bool isCXXRecord() const;

    public bool hasDefinition() const;

    public const RecordDeclaration getDefinition() const;

    public bool isDynamicClass() const;

    public bool isCanonical() const;

    public uint getTemplateArgumentCount() const;
}

extern (C++) interface UnionDeclaration : Declaration
{

    final public UnionType getUnionType() const;

    public FieldRange getFieldRange();

    public DeclarationRange getChildren();

    public uint getTemplateArgumentCount() const;
}

extern (C++) interface TemplateArgumentIterator
{

    public void advance();

    public bool equals(TemplateArgumentIterator other);

    public TemplateArgumentIterator.Kind getKind();

    public bool isPack();

    public TemplateTypeArgumentDeclaration getType();

    public TemplateNonTypeArgumentDeclaration getNonType();

    enum Kind : uint 

    {
Type = 0,
NonType = 1
    }
}

extern (C++) interface TemplateDeclaration
{

    public uint getTemplateArgumentCount() const;

    public TemplateArgumentIterator getTemplateArgumentBegin();

    public TemplateArgumentIterator getTemplateArgumentEnd();
}

extern (C++) interface SpecializedRecordDeclaration : RecordDeclaration
{

    public TemplateArgumentInstanceIterator getTemplateArgumentBegin();

    public TemplateArgumentInstanceIterator getTemplateArgumentEnd();
}

extern (C++) interface SpecializedRecordRange
{

    public SpecializedRecordDeclaration front();

    public void popFront();

    public bool empty() const;
}

extern (C++) interface RecordTemplateDeclaration : RecordDeclaration
{

    final public bool isVariadic() const;

    public TemplateArgumentIterator getTemplateArgumentBegin() const;

    public TemplateArgumentIterator getTemplateArgumentEnd() const;

    public SpecializedRecordRange getSpecializationRange();
}

extern (C++) interface UnionTemplateDeclaration : UnionDeclaration
{

    public TemplateArgumentIterator getTemplateArgumentBegin();

    public TemplateArgumentIterator getTemplateArgumentEnd();
}

extern (C++) interface TemplateTypeArgumentDeclaration : Declaration
{

    final public TemplateArgumentType getTemplateArgumentType() const;
}

extern (C++) interface TemplateNonTypeArgumentDeclaration : Declaration {}

extern (C++) interface UnwrappableDeclaration : Declaration {}

extern (C++) void traverseDeclsInAST(clang.ASTUnit* ast);

extern (C++) void enableDeclarationsInFiles(size_t count, char** filenames);

extern (C++) void arrayOfFreeDeclarations(size_t* count, Declaration** array);

extern (C++) Declaration getDeclaration(const(clang.Decl)* decl);

extern (C++) interface SkipUnwrappableDeclaration : NotWrappableException {}

extern (C++) extern const(clang.SourceManager)* source_manager;

extern (C++) interface ExpressionVisitor
{

    public void visit(IntegerLiteralExpression expr);

    public void visit(DeclaredExpression expr);

    public void visit(DelayedExpression expr);

    public void visit(UnwrappableExpression expr);
}

extern (C++) interface Expression
{

    public void dump() const;

    public void visit(ExpressionVisitor visitor);
}

extern (C++) interface IntegerLiteralExpression : Expression
{

    final public long getValue() const;
}

extern (C++) interface DeclaredExpression : Expression
{

    final public Declaration getDeclaration() const;
}

extern (C++) interface DelayedExpression : Expression
{

    final public Declaration getDeclaration() const;
}

extern (C++) interface UnwrappableExpression : Expression {}

extern (C++) clang.ASTUnit* buildAST(char* contents, size_t arg_len, char** raw_args, char* filename);
