#import "OakDocumentControllerCxx.h"

@implementation OakDocumentController (Cxx)
- (void)showDocument:(OakDocument*)aDocument
{
	[self showDocument:aDocument andSelect:text::range_t::undefined inProject:nil bringToFront:YES];
}

- (void)showDocument:(OakDocument*)aDocument inProject:(NSUUID*)identifier bringToFront:(BOOL)bringToFront
{
	[self showDocument:aDocument andSelect:text::range_t::undefined inProject:identifier bringToFront:bringToFront];
}
@end
