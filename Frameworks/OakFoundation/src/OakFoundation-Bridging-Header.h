// The ObjC surface OakFoundation's Swift code sees. The framework's first Swift
// file is OakHistoryList (2026-09-15), which needs nothing from here but
// Foundation; the prelude comes first because the Swift Clang importer compiles
// this standalone with no GCC_PREFIX_HEADER, and OakFoundation.h declares a
// std::string function under __cplusplus (see CommitWindow-Bridging-Header.h).
//
// Deliberately absent: OakHistoryList.h. Swift defines that class; the header
// is the hand-written declaration for the consumers (rule 43).
#include "../../../Shared/PCH/prelude.cc"
#import <Foundation/Foundation.h>

#import "OakFoundation.h"
