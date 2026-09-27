#import "MTCore.h"

static BOOL BoolProperty(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return MTMatches(object, selector, "B@:") && ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

BOOL MTBlocksCaption(NSString *caption, NSArray<NSString *> *tags) {
    if (![caption isKindOfClass:NSString.class] || !caption.length || caption.length > 16000 || !tags.count) return NO;
    static NSRegularExpression *expression;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ expression = [NSRegularExpression regularExpressionWithPattern:@"#([\\p{L}\\p{N}_]+)" options:0 error:nil]; });
    NSString *lower = [caption lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    for (NSTextCheckingResult *match in [expression matchesInString:lower options:0 range:NSMakeRange(0, lower.length)]) {
        if ([tags containsObject:[lower substringWithRange:[match rangeAtIndex:1]]]) return YES;
    }
    return NO;
}

NSArray *MTFilterFeed(NSArray *items) {
    if (![items isKindOfClass:NSArray.class]) return items;
    BOOL ads = MTBool(@"hide_ads"), live = MTBool(@"hide_live"), photos = MTBool(@"hide_photos");
    NSArray *tags = MTBool(@"blocked_tags_on") ? MTValue(@"blocked_tags") : @[];
    if (!ads && !live && !photos && !tags.count) return items;
    id account = MTGet(NSClassFromString(@"AWEUserService"), @"sharedService");
    NSString *uid = MTGet(account, @"userID");
    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    NSMutableArray *filtered;
    NSUInteger index = 0;
    for (id item in items) {
        BOOL drop = NO;
        if ([item isKindOfClass:awemeClass]) {
            NSString *author = MTGet(MTGet(item, @"author"), @"userID");
            BOOL mine = [uid isKindOfClass:NSString.class] && uid.length && [uid isEqual:author];
            if (!mine) {
                id liveID = MTGet(item, @"liveId");
                BOOL room = ([liveID isKindOfClass:NSNumber.class] && [liveID longLongValue] != 0) || MTGet(item, @"room") != nil;
                SEL type = NSSelectorFromString(@"awemeType");
                if (MTMatches(item, type, "q@:")) room |= ((NSInteger (*)(id, SEL))objc_msgSend)(item, type) == 101;
                drop = (ads && BoolProperty(item, @"isAds")) || (live && room);
                if (!room) drop |= (photos && MTGet(item, @"photoAlbum") != nil) || MTBlocksCaption(MTGet(item, @"descriptionString"), tags);
            }
        }
        if (drop && !filtered) filtered = [[items subarrayWithRange:NSMakeRange(0, index)] mutableCopy];
        if (!drop && filtered) [filtered addObject:item];
        index++;
    }
    return filtered ?: items;
}

static BOOL BoolHook(NSString *cls, NSString *selector, NSString *key, BOOL value) {
    SEL sel = NSSelectorFromString(selector);
    return MTHook(cls, selector, NO, "B@:", ^id(IMP original) {
        return ^BOOL(id object) {
            return MTBool(key) ? value : ((BOOL (*)(id, SEL))original)(object, sel);
        };
    });
}

static BOOL UsableURL(id model) {
    id urls = MTGet(model, @"originURLList");
    if (![urls isKindOfClass:NSArray.class]) return NO;
    for (id entry in urls) {
        NSURL *url = [entry isKindOfClass:NSURL.class] ? entry : [entry isKindOfClass:NSString.class] ? [NSURL URLWithString:entry] : nil;
        if (url.host.length && [@[@"https", @"http"] containsObject:url.scheme.lowercaseString]) return YES;
    }
    return NO;
}
static BOOL URLHook(NSString *cls, NSString *selector, NSArray *alternatives) {
    SEL sel = NSSelectorFromString(selector);
    return MTHook(cls, selector, NO, "@@:", ^id(IMP original) {
        return ^id(id object) {
            id before = ((id (*)(id, SEL))original)(object, sel);
            if (!MTBool(@"download_no_watermark")) return before;
            for (NSString *alternative in alternatives) {
                id clean = MTGet(object, alternative);
                if (UsableURL(clean)) return clean;
            }
            return before;
        };
    });
}

static void SetObject(id object, NSString *name, id value) {
    SEL selector = NSSelectorFromString(name);
    if (MTMatches(object, selector, "v@:@")) ((void (*)(id, SEL, id))objc_msgSend)(object, selector, value);
}

@interface MTEntry : NSObject
+ (instancetype)shared;
- (void)open:(id)sender;
@end
@implementation MTEntry
+ (instancetype)shared {
    static MTEntry *entry;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ entry = [MTEntry new]; });
    return entry;
}
- (void)open:(id)sender {
    UIWindow *window = [sender isKindOfClass:UIView.class] ? [sender window] : MTActiveWindow();
    MTPresentSettings(MTTopController(window));
}
@end

@protocol MTSettingsConstructors <NSObject>
- (instancetype)initWithIdentifier:(NSString *)identifier;
- (instancetype)initWithPluginContext:(id)context;
@end

static void AddSettingsRow(id section) {
    if (![MTGet(section, @"sectionIdentifier") isEqual:@"account"]) return;
    NSArray *models = MTGet(section, @"modelsArray");
    if (![models isKindOfClass:NSArray.class]) return;
    for (id model in models) if ([MTGet(MTGet(model, @"itemModel"), @"identifier") isEqual:@"margyt_ios_settings"]) return;
    Class itemClass = NSClassFromString(@"AWESettingItemModel");
    Class pluginClass = NSClassFromString(@"TTKSettingsBaseCellPlugin");
    SEL insert = NSSelectorFromString(@"insertModel:atIndex:animated:");
    if (!itemClass || !pluginClass || !MTMatches(section, insert, "v@:@qB")) return;
    id<MTSettingsConstructors> itemAllocation = [itemClass alloc];
    if (!MTMatches(itemAllocation, @selector(initWithIdentifier:), "@@:@")) return;
    id item = [itemAllocation initWithIdentifier:@"margyt_ios_settings"];
    SetObject(item, @"setIdentifier:", @"margyt_ios_settings");
    SetObject(item, @"setTitle:", MTText(@"Настройки MargyT", @"MargyT settings"));
    SetObject(item, @"setDetail:", @"MargyT · iOS");
    SetObject(item, @"setIconImage:", [UIImage systemImageNamed:@"slider.horizontal.3"]);
    SEL type = NSSelectorFromString(@"setType:");
    if (MTMatches(item, type, "v@:q")) ((void (*)(id, SEL, NSInteger))objc_msgSend)(item, type, 99);
    id<MTSettingsConstructors> pluginAllocation = [pluginClass alloc];
    if (!MTMatches(pluginAllocation, @selector(initWithPluginContext:), "@@:@")) return;
    id plugin = [pluginAllocation initWithPluginContext:MTGet(section, @"context")];
    SetObject(plugin, @"setItemModel:", item);
    if (![MTGet(MTGet(plugin, @"itemModel"), @"identifier") isEqual:@"margyt_ios_settings"]) return;
    ((void (*)(id, SEL, id, NSInteger, BOOL))objc_msgSend)(section, insert, plugin, 0, NO);
    MTNote(@"MargyT row added to account settings");
}

static void InstallEntries(void) {
    BOOL live = MTHook(@"AWELiveFeedEntranceView", @"buttonAction:", NO, "v@:@", ^id(IMP original) {
        return ^(UIView *view, id sender) {
            UIViewController *top = MTTopController(view.window);
            if (MTBool(@"live_menu") && top && top.view.window && !top.isBeingDismissed && !top.isBeingPresented && !top.presentedViewController) MTPresentSettings(top);
            else ((void (*)(id, SEL, id))original)(view, NSSelectorFromString(@"buttonAction:"), sender);
        };
    });
    MTCapability(@"live_menu", live);
    BOOL selected = MTHook(@"TTKSettingsBaseCellPlugin", @"didSelectItemAtIndex:", NO, "v@:q", ^id(IMP original) {
        return ^(id plugin, NSInteger index) {
            if ([MTGet(MTGet(plugin, @"itemModel"), @"identifier") isEqual:@"margyt_ios_settings"]) [MTEntry.shared open:nil];
            else ((void (*)(id, SEL, NSInteger))original)(plugin, NSSelectorFromString(@"didSelectItemAtIndex:"), index);
        };
    });
    if (selected) MTHook(@"AWESettingsNormalSectionViewModel", @"viewDidLoad", NO, "v@:", ^id(IMP original) {
        return ^(id section) {
            ((void (*)(id, SEL))original)(section, @selector(viewDidLoad));
            @try { AddSettingsRow(section); }
            @catch (NSException *exception) { MTNote(@"Settings row unavailable; use navigation button"); }
        };
    });
    MTHook(@"TTKSettingsViewController", @"viewDidAppear:", NO, "v@:B", ^id(IMP original) {
        return ^(UIViewController *controller, BOOL animated) {
            ((void (*)(id, SEL, BOOL))original)(controller, @selector(viewDidAppear:), animated);
            for (UIBarButtonItem *button in controller.navigationItem.rightBarButtonItems) if ([button.accessibilityIdentifier isEqual:@"margyt.settings"]) return;
            UIBarButtonItem *button = [[UIBarButtonItem alloc] initWithTitle:@"MargyT" style:UIBarButtonItemStylePlain target:MTEntry.shared action:@selector(open:)];
            button.accessibilityIdentifier = @"margyt.settings";
            NSMutableArray *buttons = [controller.navigationItem.rightBarButtonItems mutableCopy] ?: [NSMutableArray array];
            [buttons addObject:button];
            controller.navigationItem.rightBarButtonItems = buttons;
        };
    });
}

static void InstallRegion(void) {
    static NSDictionary *country;
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ country = MTCountry(); enabled = MTBool(@"region_enabled"); });
    NSDictionary *carrier = @{@"isoCountryCode": country[@"iso"], @"mobileCountryCode": country[@"mcc"], @"mobileNetworkCode": country[@"mnc"], @"carrierName": country[@"carrier"]};
    BOOL ready = NO;
    for (NSString *name in carrier) {
        ready |= MTHook(@"CTCarrier", name, NO, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? carrier[name] : ((id (*)(id, SEL))original)(object, NSSelectorFromString(name)); };
        });
    }
    NSDictionary *regions = @{@"carrierRegion": [country[@"iso"] uppercaseString], @"systemRegion": [country[@"iso"] uppercaseString], @"mccmnc": [country[@"mcc"] stringByAppendingString:country[@"mnc"]]};
    for (NSString *name in regions) {
        ready |= MTHook(@"TIKTOKRegionManager", name, YES, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? regions[name] : ((id (*)(id, SEL))original)(object, NSSelectorFromString(name)); };
        });
    }
    MTCapability(@"region_enabled", ready);
    MTCapability(@"region_country", ready);
}

void MTInstallHooks(void) {
    InstallEntries();
    InstallRegion();
    BOOL feed = MTHook(@"TTKFeedBaseResponseModel", @"awemeList", NO, "@@:", ^id(IMP original) {
        return ^id(id object) {
            id items = ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"awemeList"));
            @try { return MTFilterFeed(items); }
            @catch (NSException *exception) { return items; }
        };
    });
    for (NSString *key in @[@"hide_ads", @"hide_live", @"hide_photos", @"blocked_tags", @"blocked_tags_on"]) MTCapability(key, feed);
    BOOL seekbar = BoolHook(@"AWEAwemeModel", @"progressBarVisible", @"seekbar_always", YES);
    seekbar &= BoolHook(@"AWEAwemeModel", @"progressBarDraggable", @"seekbar_always", YES);
    MTCapability(@"seekbar_always", seekbar);
    MTCapability(@"always_date", BoolHook(@"AWEPlayInteractionAuthorElement", @"shouldShowTimeStampLabel", @"always_date", YES));
    BOOL sound = BoolHook(@"AWEAwemeModel", @"musicIsMuted", @"sound_available", NO);
    sound |= BoolHook(@"AWEAwemeModel", @"musicIsMutedDueToCopyrightViolation", @"sound_available", NO);
    BoolHook(@"AWEMusicModel", @"shouldMuteShare", @"sound_available", NO);
    MTCapability(@"sound_available", sound);
    BOOL downloads = URLHook(@"AWEVideoModel", @"downloadURL", @[@"downloadNoWatermarkURL", @"playURL"]);
    URLHook(@"AWEVideoModel", @"h264DownloadURL", @[@"downloadNoWatermarkURL", @"playURL"]);
    URLHook(@"AWEPhotoAlbumPhoto", @"ownerWatermarkedPhotoURL", @[@"originPhotoURL"]);
    URLHook(@"AWEPhotoAlbumPhoto", @"userWatermarkedPhotoURL", @[@"originPhotoURL"]);
    MTCapability(@"download_no_watermark", downloads);
    BOOL save = BoolHook(@"AWEAwemeModel", @"preventDownload", @"download_always", NO);
    BoolHook(@"AWEAwemeModel", @"disableDownload", @"download_always", NO);
    BoolHook(@"AWEUserModel", @"preventDownload", @"download_always", NO);
    MTCapability(@"download_always", save);
    MTCapability(@"no_hdr", BoolHook(@"AWEAwemeModel", @"enableHDR", @"no_hdr", NO));
    MTInstallAppearance();
}

__attribute__((constructor)) static void MTStart(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if (![[bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"TikTok"] || ![bundle.bundlePath.pathExtension isEqual:@"app"]) return;
        if (![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"46.9.0"]) return;
        MTNote(@"Starting development port; on-device compatibility unverified");
        InstallRegion();
        dispatch_async(dispatch_get_main_queue(), ^{
            MTInstallHooks();
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { MTInstallHooks(); }];
        });
    }
}
