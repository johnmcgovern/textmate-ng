@protocol HOWebViewDelegateHelperProtocol
@property (nonatomic) NSString* statusText;
@end

@interface HOWebViewDelegateHelper : NSObject <WKUIDelegate>
@property (nonatomic, weak) id /*<HOWebViewDelegateHelperProtocol>*/ delegate;
@end
