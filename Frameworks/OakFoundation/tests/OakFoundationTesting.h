// What the OakFoundation tests reach that consumers do not need.
//
// In its own header because ide/gen_xctest.rb wraps each test file's body in
// `namespace <basename>` and an ObjC declaration may only appear at global
// scope — but every #import is hoisted, so a class declared here is fine. Same
// arrangement as BundlesManager/tests/BundlesManagerTesting.h.
#import "../src/OakHistoryList.h"
#import <Foundation/Foundation.h>

// Records the key paths it is told about, in order. t_history_list.mm pins the
// KVO surface the Find window's bindings depend on with it.
@interface HistoryObserver : NSObject
@property (nonatomic) NSMutableArray<NSString*>* keys;
@end

@implementation HistoryObserver
- (void)observeValueForKeyPath:(NSString*)keyPath ofObject:(id)object change:(NSDictionary*)change context:(void*)context
{
	[self.keys addObject:keyPath];
}
@end
