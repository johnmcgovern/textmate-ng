// Hand-declared (rule 23): OakEncodingPopUpButton is defined in
// OakEncodingPopUpButton.swift.
//
// Unchanged from when this was the real header — the surface was always
// C++-free. It stays for the ObjC++ consumers (OakDocument, EncodingView,
// OakSavePanel) and must not appear in OakAppKit's own bridging header, where it
// would collide with the generated OakAppKit-Swift.h (rule 43).
@interface OakEncodingPopUpButton : NSPopUpButton
@property (nonatomic) NSString* encoding;
@end
