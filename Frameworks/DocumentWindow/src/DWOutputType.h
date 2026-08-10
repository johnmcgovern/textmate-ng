// Where a filter command's output goes, in a form that crosses the ObjC boundary.
//
// The ObjC spelling of `output::type` from <command/parser.h>, and the third
// enum split this project has made for the same reason — after `scm::status::type`
// (TMSCMStatus.h) and `find::options_t` (FFFindOptions.h). The C++ enum's
// underlying type is whatever the compiler picks; any ObjC or Swift declaration
// of the property uses NSInteger. That mismatch is neither an error nor a
// warning, and it has already cost this project once.
//
// **This one is persisted**, which is what makes it a decision rather than
// tidiness: OakRunCommandWindowController writes the raw integer to the
// `filterOutputType` user default and reads it back on the next launch. A
// renumbering would silently change what Filter Through Command does to your
// document — replacing it rather than inserting after it, say. The values are
// therefore pinned twice: by static_assert in DocumentWindowSupport.mm, and by
// t_output_type.mm at runtime, because the static_assert lives in a file that
// exists only as long as the C++ does. TMSCMStatus.h still cites a static_assert
// in a file that was ported away, taking the assertions with it; the runtime
// table is what survived.
//
// All eight values are mirrored even though the Filter Through Command menu
// offers four. The property is initialised from the stored default, so it can
// hold any of them.
//
// Deliberately free of C++ so a Swift bridging header can import it.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DWOutputType) {
	DWOutputTypeReplaceInput = 0,
	DWOutputTypeReplaceDocument,
	DWOutputTypeAtCaret,
	DWOutputTypeAfterInput,
	DWOutputTypeNewWindow,
	DWOutputTypeToolTip,
	DWOutputTypeDiscard,
	DWOutputTypeReplaceSelection,
};
