// Hand-declared (rule 23): this class is defined in
// HOWebViewDelegateHelper.swift.
//
// It must not appear in HTMLOutput-Bridging-Header.h, where it would collide with
// the generated HTMLOutput-Swift.h (rule 43).
#import <WebKit/WebKit.h>
@protocol HOWebViewDelegateHelperProtocol
@property (nonatomic) NSString* statusText;
@end

@interface HOWebViewDelegateHelper : NSObject <WKUIDelegate>
@property (nonatomic, weak) id /*<HOWebViewDelegateHelperProtocol>*/ delegate;
@end
