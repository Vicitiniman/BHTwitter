#import "HookHelpers.h"
#import "Likes/BHTLikesTab.h"

@interface T1TabView (BHTLikesTap)
@property(nonatomic, strong) UITapGestureRecognizer* bhtLikesTapGesture;
@end

// Capture the native private Likes timeline after the ad/timeline filters have
// done their work.  The native controller remains responsible for pagination.
%hook TFNItemsDataViewController

- (void)setSections:(NSArray*)sections restoreScrollPosition:(BOOL)restoreScrollPosition {
    BHTCaptureLikesSections((UIViewController*)self, sections);
    %orig;
}

- (void)updateSections:(NSArray*)sections
    reconfigureItemIdentifiers:(NSArray*)identifiers
              withRowAnimation:(long long)animation
                    completion:(id)completion {
    BHTCaptureLikesSections((UIViewController*)self, sections);
    %orig;
}

%end

%hook T1TabView

%property(nonatomic, strong) UITapGestureRecognizer* bhtLikesTapGesture;

- (NSString*)title {
    return [self.scribePage isEqualToString:BHTLikesPageID()] ? @"My Likes" : %orig;
}

- (NSString*)imageName {
    return [self.scribePage isEqualToString:BHTLikesPageID()] ? @"heart_stroke" : %orig;
}

- (void)_t1_updateTitleLabel {
    %orig;
    if ([self.scribePage isEqualToString:BHTLikesPageID()]) {
        self.titleLabel.text = @"Likes";
    }
}

- (void)layoutSubviews {
    %orig;
    BOOL isLikes = [self.scribePage isEqualToString:BHTLikesPageID()] &&
                   [BHTSettings boolForKey:@"enable_likes_tab"];
    if (!self.bhtLikesTapGesture) {
        UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc]
            initWithTarget:self
                    action:@selector(bht_openLikes:)];
        tap.cancelsTouchesInView = YES;
        tap.delaysTouchesEnded = YES;
        tap.enabled = NO;
        [self addGestureRecognizer:tap];
        self.bhtLikesTapGesture = tap;
    }

    self.bhtLikesTapGesture.enabled = isLikes;
    if (!isLikes) return;

    // The Likes destination reuses X's Grok entry for its visual slot. X may
    // select that entry with a recognizer on either T1TabView or an ancestor.
    // Make every native tap recognizer wait for ours; ours succeeds on the
    // Likes slot, cancelling the underlying Grok selection before presenting
    // the native Likes controller.
    self.userInteractionEnabled = YES;
    UIView* current = self;
    for (NSUInteger depth = 0; current && depth < 4;
         depth++, current = current.superview) {
        for (UIGestureRecognizer* recognizer in current.gestureRecognizers) {
            if (recognizer != self.bhtLikesTapGesture &&
                [recognizer isKindOfClass:UITapGestureRecognizer.class]) {
                [recognizer requireGestureRecognizerToFail:
                                self.bhtLikesTapGesture];
            }
        }
    }
}

%new
- (void)bht_openLikes:(id)sender {
    BHTPresentLikesFromView(self);
}

%end
