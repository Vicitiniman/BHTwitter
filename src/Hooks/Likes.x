#import "HookHelpers.h"
#import "Likes/BHTLikesTab.h"

@interface T1TabView (BHTLikesOverlay)
@property(nonatomic, strong) UIControl* bhtLikesOverlay;
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

%property(nonatomic, strong) UIControl* bhtLikesOverlay;

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
    if (isLikes && !self.bhtLikesOverlay) {
        UIControl* overlay = [[UIControl alloc] initWithFrame:self.bounds];
        overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        overlay.accessibilityLabel = @"My Likes";
        overlay.accessibilityTraits = UIAccessibilityTraitButton;
        [overlay addTarget:self
                    action:@selector(bht_openLikes:)
          forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:overlay];
        self.bhtLikesOverlay = overlay;
    }
    self.bhtLikesOverlay.hidden = !isLikes;
    if (isLikes) [self bringSubviewToFront:self.bhtLikesOverlay];
}

%new
- (void)bht_openLikes:(id)sender {
    BHTPresentLikesFromView(self);
}

%end
