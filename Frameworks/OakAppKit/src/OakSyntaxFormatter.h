// Hand-declared (rule 23): OakSyntaxFormatter is defined in
// OakSyntaxFormatter.swift.
//
// The declaration below is unchanged from when this was the real header — the
// class's surface was already C++-free, which is why only its *implementation*
// needed the OakSyntaxFormatterSupport split. It stays here for Find's
// FFTextFieldViewController, the one ObjC++ consumer, and it must not appear in
// OakAppKit's own bridging header, where it would collide with the generated
// OakAppKit-Swift.h (rule 43).
@interface OakSyntaxFormatter : NSFormatter
- (instancetype)initWithGrammarName:(NSString*)grammarName;
- (void)addStylesToString:(NSMutableAttributedString*)str;
@property (nonatomic) BOOL enabled;
@end
