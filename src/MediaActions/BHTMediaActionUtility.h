#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, BHTMediaActionKind) {
    BHTMediaActionKindPhoto = 0,
    BHTMediaActionKindVideo = 1,
    BHTMediaActionKindGIF = 2,
};

FOUNDATION_EXPORT NSString* const BHTMediaActionLikeIdentifier;
FOUNDATION_EXPORT NSString* const BHTMediaActionCopyLinkIdentifier;
FOUNDATION_EXPORT NSString* const BHTMediaActionReactIdentifier;
FOUNDATION_EXPORT NSString* const BHTMediaActionOfflineIdentifier;
FOUNDATION_EXPORT NSString* const BHTMediaActionDownloadIdentifier;
FOUNDATION_EXPORT NSString* const BHTMediaActionShareFileIdentifier;
FOUNDATION_EXPORT NSString* const BHTMediaActionShareViaIdentifier;
FOUNDATION_EXPORT NSString* const
    BHTMediaActionPreferencesDidChangeNotification;

// Associates an action created by NeoFreeBird with a stable identifier. Native
// TFNActionItems are identified from their titles when no explicit identifier
// has been attached.
FOUNDATION_EXPORT void BHTMediaActionSetIdentifier(
    nullable id item, NSString* identifier);

// Removes hidden known actions and orders the remaining known actions according
// to the selected media type. Unknown and cancel items are always preserved.
FOUNDATION_EXPORT NSArray* BHTMediaActionApplyPreferences(
    NSArray* items, BHTMediaActionKind kind);

@interface BHTMediaActionUtility : NSObject

+ (NSArray<NSString*>*)canonicalActionIdentifiers;
+ (NSArray<NSDictionary*>*)availableActionsForKind:
    (BHTMediaActionKind)kind;
+ (nullable NSDictionary*)metadataForIdentifier:(NSString*)identifier
                                            kind:(BHTMediaActionKind)kind;

+ (NSArray<NSString*>*)orderedActionIdentifiersForKind:
    (BHTMediaActionKind)kind;
+ (NSArray<NSString*>*)hiddenActionIdentifiersForKind:
    (BHTMediaActionKind)kind;
+ (NSArray<NSString*>*)visibleActionIdentifiersForKind:
    (BHTMediaActionKind)kind;

+ (void)setOrderedActionIdentifiers:(NSArray<NSString*>*)ordered
            hiddenActionIdentifiers:(NSArray<NSString*>*)hidden
                                kind:(BHTMediaActionKind)kind;
+ (void)resetPreferencesForKind:(BHTMediaActionKind)kind;

@end

NS_ASSUME_NONNULL_END
