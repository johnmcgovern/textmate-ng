// Hand-written ObjC declaration of the Swift FavoriteChooser (Favorites.swift), for the
// app's ObjC++ menu handler and for t_favorites.mm, which pins the contract (rule 18).
// Kept out of the bridging header: Swift defines the class (rule 43).
#import "OakChooser.h"

@interface FavoriteChooser : OakChooser
@property (class, readonly) FavoriteChooser* sharedInstance;
@end
