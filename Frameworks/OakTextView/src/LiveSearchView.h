// Hand-declared (rule 23): this class is defined in LiveSearchView.swift.
//
// It must not appear in OakTextView-Bridging-Header.h, where it would collide
// with the generated OakTextView-Swift.h (rule 43).
#import <OakAppKit/OakUIConstructionFunctions.h>

@interface LiveSearchView : OakBackgroundFillView
@property (nonatomic) NSTextField* textField;
@property (nonatomic) NSButton* ignoreCaseCheckBox;
@property (nonatomic) NSButton* wrapAroundCheckBox;
@end
