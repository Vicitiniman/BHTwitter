#import <UIKit/UIKit.h>

// Reuses the native Grok navigation entry as an opt-in My Likes button. The
// entry object itself stays native so the app's tab/controller arrays and Swift
// casts remain valid across X releases; only its root controller is replaced.
NSArray* BHTEntriesByInstallingLikesDestination(NSArray* entries);

// Called by the timeline section hook while a private Likes timeline is active.
// Returns YES when the data controller belongs to the private Likes timeline,
// allowing the caller to suppress X's saved scroll-position restoration.
BOOL BHTCaptureLikesSections(UIViewController* dataViewController, NSArray* sections);

// Called when the real tab changes from unselected to selected. This resets
// both Posts and Media to their newest item without disturbing swipe-back from
// a post or the media pager.
void BHTActivateLikesTabView(UIView* tabView);

// Privacy-safe runtime diagnostics included in the compatibility export.
NSDictionary* BHTLikesDiagnosticsSnapshot(void);

// Applies the setting without requiring a relaunch.
void BHTRefreshVisibleAppTabs(void);

NSString* BHTLikesPageID(void);
