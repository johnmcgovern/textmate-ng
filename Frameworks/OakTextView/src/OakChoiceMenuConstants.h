// The five key-action codes OakChoiceMenu returns from -didHandleKeyEvent:.
//
// They stay in ObjC because Swift cannot export an `extern` constant (rule 19),
// and unlike most such cases this one will never lift: the only consumer is
// OakTextView.mm, which subclasses three C++ classes with virtual methods and is
// not a porting candidate at all.
//
// The values are an ABI — OakTextView.mm branches on them — and t_choice_menu.mm
// asserts them, because nothing else would notice a renumbering.
extern NSUInteger const OakChoiceMenuKeyUnused;
extern NSUInteger const OakChoiceMenuKeyReturn;
extern NSUInteger const OakChoiceMenuKeyTab;
extern NSUInteger const OakChoiceMenuKeyCancel;
extern NSUInteger const OakChoiceMenuKeyMovement;
