// Unified prefix header for the Xcode build (Phase 2 / Stream 1).
//
// rave compiles every translation unit with a language-specific prelude
// (prelude.c / prelude.cc / prelude.m / prelude.mm). Xcode allows only a single
// GCC_PREFIX_HEADER per target, so this dispatches to the right prelude based on
// the language of the current translation unit. This lets one target mix C, C++,
// ObjC and ObjC++ sources (including generated .capnp.c++ / .cc) under one PCH.
#if defined(__OBJC__) && defined(__cplusplus)
    #include "prelude.mm"
#elif defined(__OBJC__)
    #include "prelude.m"
#elif defined(__cplusplus)
    #include "prelude.cc"
#else
    #include "prelude.c"
#endif
