#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const BHTLikesBookmarksPageID;
extern NSString* const BHTLikesVideosPageID;
extern NSString* const BHTLikesArticlesPageID;
extern NSString* const BHTLikesPostsPageID;
extern NSString* const BHTLikesNavigationSettingsDidChangeNotification;

@interface BHTLikesNavigationUtility : NSObject

// Metadata for the four native Activity History destinations.
+ (NSArray<NSDictionary*>*)availableTabs;
+ (nullable NSDictionary*)metadataForPage:(NSString*)pageID;

// The visible destinations in the order selected in the Likes editor.
+ (NSArray<NSString*>*)visiblePageIDsInOrder;
+ (void)setVisiblePageIDs:(NSArray<NSString*>*)visible;
+ (void)resetSelection;
+ (BOOL)waterfallEnabled;
+ (void)setWaterfallEnabled:(BOOL)enabled;

// X 12.9 builds Activity History in this canonical order. These helpers map
// the editor's visible order onto the native data-source indices.
+ (NSInteger)originalIndexForPageID:(NSString*)pageID;
+ (NSInteger)originalIndexForVisibleIndex:(NSInteger)visibleIndex
                         originalCount:(NSInteger)originalCount;
+ (NSInteger)visibleIndexForOriginalIndex:(NSInteger)originalIndex
                         originalCount:(NSInteger)originalCount;
+ (NSInteger)visibleIndexForPageID:(NSString*)pageID
                      originalCount:(NSInteger)originalCount;
+ (NSArray<NSString*>*)visiblePageIDsForOriginalCount:(NSInteger)originalCount;

@end

NS_ASSUME_NONNULL_END
