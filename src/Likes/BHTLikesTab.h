#import <UIKit/UIKit.h>

// Reuses the native Grok navigation entry as an opt-in My Likes button.  The
// entry object itself stays native so the app's tab/controller arrays and Swift
// casts remain valid across X releases.
NSArray* BHTEntriesByInstallingLikesDestination(NSArray* entries);

// Called by the timeline section hook while a private Likes timeline is active.
void BHTCaptureLikesSections(UIViewController* dataViewController, NSArray* sections);

// Applies the setting without requiring a relaunch.
void BHTRefreshVisibleAppTabs(void);
void BHTPresentLikesFromView(UIView* sourceView);

NSString* BHTLikesPageID(void);
