#import "MTCore.h"
#import <QuartzCore/QuartzCore.h>

static char MTAlphaKey;
static char MTGestureKey;
static NSHashTable<UIView *> *dimmed;
static IMP alphaOriginal;

static CGFloat Dimmed(CGFloat alpha) {
    CGFloat percent = MAX(0, MIN(90, [MTValue(@"dim_how") doubleValue]));
    return MTBool(@"dim_on") ? alpha * (1 - percent / 100) : alpha;
}
static NSInteger RequestedFPS(void) {
    NSInteger requested = [MTValue(@"fps_lock") integerValue];
    return requested > 0 ? MIN(requested, UIScreen.mainScreen.maximumFramesPerSecond) : 0;
}

@interface MTImageShare : NSObject <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *view;
@property (nonatomic, copy) NSString *key;
- (void)held:(UILongPressGestureRecognizer *)gesture;
@end
@implementation MTImageShare
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)recognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer { return MTBool(self.key); }
- (void)held:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state != UIGestureRecognizerStateBegan || !MTBool(self.key)) return;
    id imageView = [self.key isEqual:@"save_avatars"] ? MTGet(self.view, @"avatar") : self.view;
    UIImage *image = [imageView isKindOfClass:UIImageView.class] ? ((UIImageView *)imageView).image : nil;
    UIViewController *top = MTTopController(self.view.window);
    if (!image || !top || top.presentedViewController || !top.view.window) return;
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[image] applicationActivities:nil];
    share.popoverPresentationController.sourceView = self.view;
    share.popoverPresentationController.sourceRect = self.view.bounds;
    [top presentViewController:share animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
}
@end

static BOOL InstallImageSharing(NSString *className, NSString *key) {
    return MTHook(className, @"didMoveToWindow", NO, "v@:", ^id(IMP original) {
        return ^(UIView *view) {
            ((void (*)(id, SEL))original)(view, @selector(didMoveToWindow));
            if (!view.window || objc_getAssociatedObject(view, &MTGestureKey)) return;
            MTImageShare *target = [MTImageShare new];
            target.view = view;
            target.key = key;
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:@selector(held:)];
            hold.minimumPressDuration = 0.65;
            hold.cancelsTouchesInView = NO;
            hold.delegate = target;
            [view addGestureRecognizer:hold];
            objc_setAssociatedObject(view, &MTGestureKey, target, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        };
    });
}

void MTInstallAppearance(void) {
    MTCapability(@"save_avatars", InstallImageSharing(@"AWEProfileImagePreviewView", @"save_avatars"));
    MTCapability(@"save_stickers", InstallImageSharing(@"TTKCommentStickerPreviewView", @"save_stickers"));
    BOOL font = MTHook(@"TUXLabel", @"setFont:", NO, "v@:@", ^id(IMP original) {
        return ^(UILabel *label, UIFont *requested) {
            NSString *choice = MTValue(@"font");
            NSString *design = [choice isEqual:@"rounded"] ? UIFontDescriptorSystemDesignRounded : [choice isEqual:@"serif"] ? UIFontDescriptorSystemDesignSerif : [choice isEqual:@"monospaced"] ? UIFontDescriptorSystemDesignMonospaced : nil;
            UIFontDescriptor *descriptor = design ? [requested.fontDescriptor fontDescriptorWithDesign:design] : nil;
            UIFont *font = descriptor ? [UIFont fontWithDescriptor:descriptor size:requested.pointSize] : requested;
            ((void (*)(id, SEL, id))original)(label, @selector(setFont:), font);
        };
    });
    MTCapability(@"font", font);
    BOOL alpha = MTHook(@"TTKFeedInteractionMainView", @"setAlpha:", NO, "v@:d", ^id(IMP original) {
        alphaOriginal = original;
        return ^(UIView *view, CGFloat requested) {
            objc_setAssociatedObject(view, &MTAlphaKey, @(requested), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            [dimmed addObject:view];
            ((void (*)(id, SEL, CGFloat))original)(view, @selector(setAlpha:), Dimmed(requested));
        };
    });
    if (alpha) {
        static dispatch_once_t once;
        dispatch_once(&once, ^{
            dimmed = [NSHashTable weakObjectsHashTable];
            [NSNotificationCenter.defaultCenter addObserverForName:MTSettingsChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                for (UIView *view in dimmed.allObjects) {
                    NSNumber *before = objc_getAssociatedObject(view, &MTAlphaKey);
                    if (before) ((void (*)(id, SEL, CGFloat))alphaOriginal)(view, @selector(setAlpha:), Dimmed(before.doubleValue));
                }
            }];
        });
        MTHook(@"TTKFeedInteractionMainView", @"didMoveToWindow", NO, "v@:", ^id(IMP original) {
            return ^(UIView *view) {
                ((void (*)(id, SEL))original)(view, @selector(didMoveToWindow));
                NSNumber *before = objc_getAssociatedObject(view, &MTAlphaKey);
                if (!before) {
                    before = @(view.alpha);
                    objc_setAssociatedObject(view, &MTAlphaKey, before, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                [dimmed addObject:view];
                ((void (*)(id, SEL, CGFloat))alphaOriginal)(view, @selector(setAlpha:), Dimmed(before.doubleValue));
            };
        });
    }
    MTCapability(@"dim_on", alpha);
    MTCapability(@"dim_how", alpha);
    BOOL fps = MTHook(@"CADisplayLink", @"setPreferredFramesPerSecond:", NO, "v@:q", ^id(IMP original) {
        return ^(CADisplayLink *link, NSInteger requested) {
            NSInteger rate = RequestedFPS();
            ((void (*)(id, SEL, NSInteger))original)(link, @selector(setPreferredFramesPerSecond:), rate > 0 ? rate : requested);
        };
    });
    if (@available(iOS 15.0, *)) {
        fps |= MTHook(@"CADisplayLink", @"setPreferredFrameRateRange:", NO, "v@:{", ^id(IMP original) {
            return ^(CADisplayLink *link, CAFrameRateRange requested) {
                NSInteger rate = RequestedFPS();
                CAFrameRateRange range = rate > 0 ? CAFrameRateRangeMake(rate, rate, rate) : requested;
                ((void (*)(id, SEL, CAFrameRateRange))original)(link, @selector(setPreferredFrameRateRange:), range);
            };
        });
    }
    MTCapability(@"fps_lock", fps);
}
