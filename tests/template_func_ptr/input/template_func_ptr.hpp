// Reduced from llvm::VariadicFunction

template <typename T>
struct ArrayRef { };

template <typename ResultT, typename ArgT,
          ResultT (*Func)(ArrayRef<const ArgT *>)>
struct VariadicFunction { };
