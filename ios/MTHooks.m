#import "MTCore.h"
#import <execinfo.h>
#import <fcntl.h>
#import <unistd.h>

static int MTTrailFD = -1;
static CFAbsoluteTime MTLaunchTime;

static void MTTrail(const char *text) {
    int fd = MTTrailFD;
    if (fd < 0 || !text) return;
    (void)write(fd, text, strlen(text));
    (void)write(fd, "\n", 1);
    fsync(fd);
}
static void MTTrailText(NSString *text) {
    MTTrail([NSString stringWithFormat:@"+%.1fs %@", CFAbsoluteTimeGetCurrent() - MTLaunchTime, text].UTF8String);
}

// The most recently filtered page, for the search auto-paging.
static struct { NSUInteger kept, total; CFAbsoluteTime at; } MTLastPage;

static NSString *MTUID;
static NSString *MTCachedUID(void) {
    @synchronized (NSString.class) { return MTUID; }
}
// Main thread only.
static void MTAccountRemember(void) {
    if (!NSThread.isMainThread) return;
    @try {
        id service = MTGet(NSClassFromString(@"AWEUserService"), @"sharedService");
        NSString *uid = MTGet(service, @"userID");
        NSString *sec = MTGet(MTGet(service, @"currentUserBasicModel"), @"secUserID");
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"cat.narezany.margyt.ios"];
        if ([uid isKindOfClass:NSString.class] && uid.length) {
            @synchronized (NSString.class) { MTUID = [uid copy]; }
            [defaults setObject:uid forKey:@"account_uid"];
        }
        if ([sec isKindOfClass:NSString.class] && sec.length) [defaults setObject:sec forKey:@"account_sec_uid"];
    } @catch (NSException *ignored) { }
}

static BOOL BoolProperty(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return MTMatches(object, selector, "B@:") && ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}

static long long LongProperty(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return MTMatches(object, selector, "q@:") ? ((long long (*)(id, SEL))objc_msgSend)(object, selector) : 0;
}

// A numeric getter of whatever scalar or NSNumber type the model declares.
static double NumberProperty(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    if (!object || ![object respondsToSelector:selector]) return 0;
    NSMethodSignature *signature = [object methodSignatureForSelector:selector];
    if (signature.numberOfArguments != 2) return 0;
    const char *type = signature.methodReturnType;
    while (*type && strchr("rnNoORV", *type)) type++;
    switch (*type) {
        case 'q': case 'l': return (double)((long long (*)(id, SEL))objc_msgSend)(object, selector);
        case 'Q': case 'L': return (double)((unsigned long long (*)(id, SEL))objc_msgSend)(object, selector);
        case 'i': return ((int (*)(id, SEL))objc_msgSend)(object, selector);
        case 'I': return ((unsigned int (*)(id, SEL))objc_msgSend)(object, selector);
        case 'd': return ((double (*)(id, SEL))objc_msgSend)(object, selector);
        case 'f': return ((float (*)(id, SEL))objc_msgSend)(object, selector);
        case '@': {
            id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
            return [value isKindOfClass:NSNumber.class] || [value isKindOfClass:NSString.class] ? [value doubleValue] : 0;
        }
        default: return 0;
    }
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

// Hashtags live in three places: the caption text, the attached challenges
// and the caption's text extras. Any of them counts.
static BOOL MTItemTagged(id item, NSArray<NSString *> *tags) {
    if (!tags.count) return NO;
    if (MTBlocksCaption(MTGet(item, @"descriptionString"), tags)) return YES;
    NSLocale *posix = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    NSArray *sources = @[@[@"challengeList", @"challengeName"], @[@"textExtras", @"hashtagName"]];
    for (NSArray *source in sources) {
        id list = MTGet(item, source[0]);
        if (![list isKindOfClass:NSArray.class]) continue;
        for (id entry in list) {
            NSString *name = MTGet(entry, source[1]);
            if (![name isKindOfClass:NSString.class] || !name.length) continue;
            while ([name hasPrefix:@"#"]) name = [name substringFromIndex:1];
            if ([tags containsObject:[name lowercaseStringWithLocale:posix]]) return YES;
        }
    }
    return NO;
}

static double DateBound(NSString *text, BOOL upper) {
    if (![text isKindOfClass:NSString.class] || !text.length) return 0;
    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        formatter.dateFormat = @"yyyy-MM-dd";
        formatter.lenient = NO;
    });
    NSDate *day = [formatter dateFromString:text];
    return day ? day.timeIntervalSince1970 + (upper ? 86399 : 0) : 0;
}

NSArray *MTFilterFeed(NSArray *items) {
    if (![items isKindOfClass:NSArray.class]) return items;
    BOOL ads = MTBool(@"hide_ads"), live = MTBool(@"hide_live"), photos = MTBool(@"hide_photos");
    BOOL softAds = MTBool(@"hide_soft_ads"), commission = MTBool(@"hide_commission");
    BOOL sensitive = MTBool(@"hide_sensitive"), warnings = MTBool(@"hide_warnings");
    BOOL recommends = MTBool(@"hide_recommendations"), popups = MTBool(@"hide_popups");
    BOOL shop = MTBool(@"hide_shop"), locations = MTBool(@"hide_location_ads");
    BOOL inserts = MTBool(@"hide_insert_cards"), ai = MTBool(@"hide_ai");
    NSArray *allTags = MTValue(@"blocked_tags");
    if (![allTags isKindOfClass:NSArray.class]) allTags = @[];
    BOOL only = MTBool(@"only_tags") && allTags.count;
    // One list, two meanings: in "only these" mode it is a whitelist, so it
    // cannot also hide the very posts it keeps.
    NSArray *tags = MTBool(@"blocked_tags_on") && !only ? allTags : @[];
    double after = DateBound(MTValue(@"feed_date_from"), NO), before = DateBound(MTValue(@"feed_date_to"), YES);
    if (!ads && !live && !photos && !softAds && !commission && !sensitive && !warnings && !recommends && !popups && !shop && !locations && !inserts && !ai && !tags.count && !only && !after && !before) return items;
    if (!items.count) return items;
    // TikTok reads the same page through the getter dozens of times; it is
    // filtered once per settings change. NSNull marks "nothing removed" so the
    // page never retains itself.
    static char cacheKey;
    NSInteger version = MTSettingsVersion();
    NSArray *cached = objc_getAssociatedObject(items, &cacheKey);
    if ([cached isKindOfClass:NSArray.class] && cached.count == 2 && [cached[0] integerValue] == version) {
        return cached[1] == NSNull.null ? items : cached[1];
    }
    static volatile int32_t entered;
    BOOL trace = __sync_fetch_and_add(&entered, 1) < 3;
    if (trace) MTTrailText([NSString stringWithFormat:@"feed filter enter (%lu items, %@ thread)", (unsigned long)items.count, NSThread.isMainThread ? @"main" : @"background"]);
    // This runs on TikTok's parsing threads: account services must not be
    // touched here, only the ID cached from the main thread.
    NSString *uid = MTCachedUID();
    Class awemeClass = NSClassFromString(@"AWEAwemeModel");
    NSMutableArray *filtered;
    NSMutableDictionary<NSString *, NSNumber *> *reasons;
    NSUInteger index = 0;
    for (id item in items) {
        NSString *reason = nil;
        if ([item isKindOfClass:awemeClass]) {
            NSString *author = MTGet(MTGet(item, @"author"), @"userID");
            BOOL mine = [uid isKindOfClass:NSString.class] && uid.length && [uid isEqual:author];
            double created = NumberProperty(item, @"createTime");
            if (created > 1e11) created /= 1000;
            if (created > 0 && ((after && created < after) || (before && created > before))) reason = @"date";
            if (!mine && !reason) {
                id liveID = MTGet(item, @"liveId");
                BOOL room = ([liveID isKindOfClass:NSNumber.class] && [liveID longLongValue] != 0) || MTGet(item, @"room") != nil || MTGet(item, @"streamUrlModel") != nil || BoolProperty(item, @"isLive");
                NSInteger awemeType = (NSInteger)LongProperty(item, @"awemeType");
                room |= awemeType == 101;
                BOOL tagged = MTItemTagged(item, allTags);
                if (ads && (BoolProperty(item, @"isAds") || BoolProperty(item, @"isAdsOrPseudoAds") || awemeType == 104 || awemeType == 105)) reason = @"ads";
                else if (live && room) reason = @"live";
                else if (only && !tagged) reason = @"only-tag";
                else if (!room && photos && (MTGet(item, @"photoAlbum") != nil || BoolProperty(item, @"isPhotoMode"))) reason = @"photos";
                else if (!room && tagged && tags.count) reason = @"tag";
                else if (softAds && (BoolProperty(item, @"isSoftAds") || BoolProperty(item, @"hasAd") || BoolProperty(item, @"hasAdFormURL") || BoolProperty(item, @"hasAdLandingPage"))) reason = @"soft-ads";
                else if (commission && (MTGet(item, @"promoteTagInfo") != nil || MTGet(item, @"boostTagInfo") != nil || MTGet(item, @"musicPromotionTag") != nil)) reason = @"commission";
                else if (sensitive && MTGet(item, @"riskInfoModel") != nil) reason = @"sensitive";
                else if (warnings && (MTGet(item, @"shareWarnInfoModel") != nil || MTGet(item, @"shareWarnModuleModel") != nil)) reason = @"warnings";
                else if (recommends && (BoolProperty(item, @"isRecommendUserCard") || BoolProperty(item, @"isUserRecommendBigCard") || MTGet(item, @"relationRecommendInfo") != nil || MTGet(item, @"recommendReasonStruct") != nil || [MTGet(item, @"feedRecommendUserList") count])) reason = @"recommend";
                else if (popups && [MTGet(item, @"interactionStickers") count]) reason = @"popups";
                else if (shop && (BoolProperty(item, @"isCommerce") || MTGet(item, @"commerceModel") != nil || MTGet(item, @"feedProductSelectionCardProductInfoModel") != nil || MTGet(item, @"activityPendant") != nil)) reason = @"shop";
                else if (locations && (MTGet(item, @"localServiceInfo") != nil || MTGet(item, @"poiRetagConfig") != nil || [MTGet(item, @"poiRetagText") isKindOfClass:NSString.class] || [MTGet(item, @"poiRetagSignal") boolValue])) reason = @"location";
                else if (inserts && (MTGet(item, @"card") != nil || MTGet(item, @"feed_cardInsertConfig") != nil)) reason = @"insert";
                else if (ai) {
                    id aigc = MTGet(item, @"aigcInfoModel");
                    if ((aigc && (BoolProperty(aigc, @"createByAI") || LongProperty(aigc, @"aigcLabelType") != 0)) || MTGet(item, @"moderationAigcInfoModel") != nil || MTGet(item, @"creationAICastInfo") != nil || MTGet(item, @"creationAIPortraitInfo") != nil) reason = @"ai";
                }
            }
        }
        if (reason) {
            if (!filtered) { filtered = [[items subarrayWithRange:NSMakeRange(0, index)] mutableCopy]; reasons = [NSMutableDictionary dictionary]; }
            reasons[reason] = @(reasons[reason].unsignedIntegerValue + 1);
        } else if (filtered) [filtered addObject:item];
        index++;
    }
    if (filtered) {
        NSMutableArray *parts = [NSMutableArray array];
        for (NSString *key in [reasons.allKeys sortedArrayUsingSelector:@selector(compare:)]) [parts addObject:[NSString stringWithFormat:@"%@:%@", key, reasons[key]]];
        NSString *line = [NSString stringWithFormat:@"feed: hidden %lu of %lu (%@)", (unsigned long)(items.count - filtered.count), (unsigned long)items.count, [parts componentsJoinedByString:@", "]];
        MTNote(line);
        static volatile int32_t traced;
        if (__sync_fetch_and_add(&traced, 1) < 5) MTTrailText(line);
    }
    if (trace) MTTrailText(@"feed filter exit");
    NSArray *result = filtered ? [filtered copy] : items;
    @synchronized (NSNull.class) {
        MTLastPage.kept = result.count;
        MTLastPage.total = items.count;
        MTLastPage.at = CFAbsoluteTimeGetCurrent();
    }
    objc_setAssociatedObject(items, &cacheKey, @[@(version), filtered ? result : NSNull.null], OBJC_ASSOCIATION_RETAIN);
    return result;
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
    if (![urls isKindOfClass:NSArray.class] || ![urls count]) urls = MTGet(model, @"URLList");
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

static char MTDownloadKey;
static char MTElementKey;
static NSMutableSet *pending;

static NSURL *MediaURL(id urlModel) {
    id urls = MTGet(urlModel, @"originURLList");
    if (![urls isKindOfClass:NSArray.class] || ![urls count]) urls = MTGet(urlModel, @"URLList");
    for (id entry in [urls isKindOfClass:NSArray.class] ? urls : nil) {
        NSURL *url = [entry isKindOfClass:NSURL.class] ? entry : [entry isKindOfClass:NSString.class] ? [NSURL URLWithString:entry] : nil;
        if (url.host.length && [@[@"https", @"http"] containsObject:url.scheme.lowercaseString]) return url;
    }
    return nil;
}

@interface MTDownloader : NSObject
@property (nonatomic, strong) NSMutableArray<NSURL *> *files;
- (void)present:(UIButton *)sender;
@end
@implementation MTDownloader
+ (instancetype)shared {
    static MTDownloader *downloader;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ downloader = [MTDownloader new]; downloader.files = [NSMutableArray array]; });
    return downloader;
}
- (void)finish:(NSString *)path forVideo:(BOOL)video image:(UIImage *)image {
    if (video) {
        UISaveVideoAtPathToSavedPhotosAlbum(path, self, @selector(saved:didFinishSavingWithError:contextInfo:), NULL);
    } else if (image) {
        UIImageWriteToSavedPhotosAlbum(image, self, @selector(saved:didFinishSavingWithError:contextInfo:), NULL);
    }
}
- (void)saved:(NSString *)path didFinishSavingWithError:(NSError *)error contextInfo:(void *)info {
    UIViewController *top = MTTopController(MTActiveWindow());
    if (error) MTShowMessage(top, @"MargyT", error.localizedDescription);
    else {
        [pending removeObject:self];
        dispatch_async(dispatch_get_main_queue(), ^{
            UILabel *toast = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 220, 40)];
            toast.text = MTText(@"Сохранено в галерею", @"Saved to Photos");
            toast.textAlignment = NSTextAlignmentCenter;
            toast.textColor = UIColor.whiteColor;
            toast.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
            toast.backgroundColor = [UIColor.blackColor colorWithAlphaComponent:0.75];
            toast.layer.cornerRadius = 20;
            toast.clipsToBounds = YES;
            toast.center = CGPointMake(top.view.bounds.size.width / 2, top.view.bounds.size.height * 0.75);
            toast.alpha = 0;
            [top.view addSubview:toast];
            BOOL animate = !UIAccessibilityIsReduceMotionEnabled();
            [UIView animateWithDuration:animate ? 0.25 : 0 animations:^{ toast.alpha = 1; } completion:^(BOOL done) {
                [UIView animateWithDuration:animate ? 0.3 : 0 delay:1.4 options:0 animations:^{ toast.alpha = 0; } completion:^(BOOL gone) { [toast removeFromSuperview]; }];
            }];
        });
    }
}
- (void)fetch:(NSURL *)url handler:(void (^)(NSURL *file))handler {
    NSURLSession *session = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
    [[session downloadTaskWithURL:url completionHandler:^(NSURL *temporary, NSURLResponse *response, NSError *error) {
        NSURL *file = temporary;
        if (!error && file) {
            NSString *extension = url.pathExtension.length ? url.pathExtension : @"mp4";
            NSURL *kept = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingFormat:@"margyt-%@.%@", NSUUID.UUID.UUIDString, extension]];
            if (![NSFileManager.defaultManager moveItemAtURL:file toURL:kept error:nil]) file = temporary;
            else file = kept;
            [MTDownloader.shared.files addObject:file];
        }
        dispatch_async(dispatch_get_main_queue(), ^{ handler(error ? nil : file); });
    }] resume];
}
- (void)present:(UIButton *)sender {
    id element = objc_getAssociatedObject(sender, &MTElementKey);
    id aweme = MTGet(element, @"model");
    UIViewController *top = MTTopController(sender.window);
    if (!aweme || !top || top.presentedViewController) return;
    id video = MTGet(aweme, @"video");
    id photos = MTGet(MTGet(aweme, @"photoAlbum"), @"photos");
    if (!video && ![photos count]) return;
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"MargyT" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    sheet.popoverPresentationController.sourceView = sender;
    sheet.popoverPresentationController.sourceRect = sender.bounds;
    if (video) {
        NSArray *order = MTBool(@"download_no_watermark") ? @[@"downloadNoWatermarkURL", @"playURL", @"downloadURL"] : @[@"downloadURL", @"downloadNoWatermarkURL", @"playURL"];
        [sheet addAction:[UIAlertAction actionWithTitle:MTText(@"Видео в галерею (.mp4)", @"Video to Photos (.mp4)") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSURL *url;
            for (NSString *name in order) if ((url = MediaURL(MTGet(video, name)))) break;
            if (!url) { MTShowMessage(top, @"MargyT", MTText(@"URL видео не найден", @"No video URL found")); return; }
            [self fetch:url handler:^(NSURL *file) {
                if (!file) { MTShowMessage(top, @"MargyT", MTText(@"Загрузка не удалась", @"Download failed")); return; }
                pending = pending ?: [NSMutableSet set];
                [pending addObject:self];
                [self finish:file.path forVideo:YES image:nil];
            }];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:MTText(@"Поделиться видео", @"Share video") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSURL *url;
            for (NSString *name in order) if ((url = MediaURL(MTGet(video, name)))) break;
            if (!url) { MTShowMessage(top, @"MargyT", MTText(@"URL видео не найден", @"No video URL found")); return; }
            [self fetch:url handler:^(NSURL *file) {
                if (!file) { MTShowMessage(top, @"MargyT", MTText(@"Загрузка не удалась", @"Download failed")); return; }
                UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
                share.popoverPresentationController.sourceView = sender;
                [top presentViewController:share animated:YES completion:nil];
            }];
        }]];
    }
    if ([photos isKindOfClass:NSArray.class] && [photos count]) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:MTText(@"Все фото в галерею (%lu)", @"All photos to Photos (%lu)"), (unsigned long)[photos count]] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            pending = pending ?: [NSMutableSet set];
            [pending addObject:self];
            __block NSUInteger left = [photos count];
            for (id photo in photos) {
                NSURL *url = MediaURL(MTGet(photo, MTBool(@"download_no_watermark") ? @"originPhotoURL" : @"ownerWatermarkedPhotoURL")) ?: MediaURL(MTGet(photo, @"originPhotoURL"));
                if (!url) { if (!--left) [pending removeObject:self]; continue; }
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    UIImage *image = [UIImage imageWithData:[NSData dataWithContentsOfURL:url]];
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (image) [self finish:nil forVideo:NO image:image];
                        if (!--left && !image) [pending removeObject:self];
                    });
                });
            }
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:MTText(@"Отмена", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [top presentViewController:sheet animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
}
@end

static BOOL InstallDownloadButton(void) {
    return MTHook(@"AWEPlayInteractionRightElement", @"willDisplay", NO, "v@:", ^id(IMP original) {
        return ^(id element) {
            ((void (*)(id, SEL))original)(element, @selector(willDisplay));
            if (!MTBool(@"download_button")) return;
            UIView *view = MTGet(element, @"viewIfLoaded");
            if (!view || objc_getAssociatedObject(view, &MTDownloadKey)) return;
            UIImage *icon = [UIImage systemImageNamed:@"arrow.down.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:26 weight:UIImageSymbolWeightSemibold]];
            UIButton *button = [UIButton systemButtonWithImage:icon target:MTDownloader.shared action:@selector(present:)];
            button.tintColor = UIColor.whiteColor;
            button.accessibilityIdentifier = @"margyt.download";
            button.accessibilityLabel = MTText(@"Скачать без водяного знака", @"Download without watermark");
            objc_setAssociatedObject(button, &MTElementKey, element, OBJC_ASSOCIATION_ASSIGN);
            if ([view isKindOfClass:UIStackView.class]) [(UIStackView *)view addArrangedSubview:button];
            else {
                button.frame = CGRectMake(view.bounds.size.width - 56, 12, 44, 44);
                button.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
                [view addSubview:button];
            }
            objc_setAssociatedObject(view, &MTDownloadKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        };
    });
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
            void (^add)(void) = ^{ @try { AddSettingsRow(section); } @catch (NSException *exception) { MTNote(@"Settings row unavailable; use navigation button"); } };
            if (NSThread.isMainThread) add();
            else dispatch_async(dispatch_get_main_queue(), add);
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

static NSSet *MTRegionSet(NSString *name) {
    static NSDictionary<NSString *, NSSet *> *sets;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSSet *(^list)(NSArray *) = ^NSSet *(NSArray *items) { return [NSSet setWithArray:items]; };
        sets = @{
            @"eu": list(@[@"at", @"be", @"bg", @"hr", @"cy", @"cz", @"dk", @"ee", @"fi", @"fr", @"de", @"gr", @"hu", @"ie", @"it", @"lv", @"lt", @"lu", @"mt", @"nl", @"pl", @"pt", @"ro", @"sk", @"si", @"es", @"se"]),
            @"eea": list(@[@"at", @"be", @"bg", @"hr", @"cy", @"cz", @"dk", @"ee", @"fi", @"fr", @"de", @"gr", @"hu", @"is", @"ie", @"it", @"lv", @"li", @"lt", @"lu", @"mt", @"nl", @"no", @"pl", @"pt", @"ro", @"sk", @"si", @"es", @"se"]),
            @"us": list(@[@"us"])
        };
    });
    return sets[name];
}

static void InstallRegion(void) {
    static NSDictionary *country;
    static BOOL enabled;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ country = MTCountry(); enabled = MTBool(@"region_enabled"); });
    NSString *iso = country[@"iso"], *ISO = [iso uppercaseString];
    NSString *mcc = country[@"mcc"], *mnc = country[@"mnc"];
    NSString *mccmnc = [mcc stringByAppendingString:mnc];
    BOOL ready = NO;

    // CTCarrier itself and TikTok's tspk_network_* category wrappers, which is
    // what the app actually calls in 46.9.0.
    NSDictionary *carrier = @{
        @"isoCountryCode": iso, @"tspk_network_isoCountryCode": iso,
        @"mobileCountryCode": mcc, @"tspk_network_mobileCountryCode": mcc,
        @"mobileNetworkCode": mnc, @"tspk_network_mobileNetworkCode": mnc,
        @"carrierName": country[@"carrier"], @"tspk_network_carrierName": country[@"carrier"]
    };
    for (NSString *name in carrier) {
        ready |= MTHook(@"CTCarrier", name, NO, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? carrier[name] : ((id (*)(id, SEL))original)(object, NSSelectorFromString(name)); };
        });
    }

    // The region TikTok reports to itself: region manager, store region reads
    // and per-SDK helpers.
    NSDictionary *regions = @{
        @"carrierRegion": ISO, @"systemRegion": ISO, @"mccmnc": mccmnc,
        @"region": ISO, @"localRegion": ISO, @"storeRegion": ISO, @"currentRegionV2": ISO
    };
    for (NSString *name in regions) {
        for (NSNumber *classMethod in @[@YES, @NO]) {
            ready |= MTHook(@"TIKTOKRegionManager", name, classMethod.boolValue, "@@:", ^id(IMP original) {
                return ^id(id object) { return enabled ? regions[name] : ((id (*)(id, SEL))original)(object, NSSelectorFromString(name)); };
            });
        }
    }
    // isRegion:/isInRegions: -- "is our region X?" is answered about the chosen
    // one. The dump does not pin down whether these sit on the class or the
    // instance, so both method tables are tried.
    for (NSNumber *classMethod in @[@YES, @NO]) {
        ready |= MTHook(@"TIKTOKRegionManager", @"isRegion:", classMethod.boolValue, "B@:@", ^id(IMP original) {
            return ^BOOL(id object, id region) {
                if (!enabled) return ((BOOL (*)(id, SEL, id))original)(object, NSSelectorFromString(@"isRegion:"), region);
                return [region isKindOfClass:NSString.class] && [region caseInsensitiveCompare:iso] == NSOrderedSame;
            };
        });
        ready |= MTHook(@"TIKTOKRegionManager", @"isInRegions:", classMethod.boolValue, "B@:@", ^id(IMP original) {
            return ^BOOL(id object, id list) {
                if (!enabled || (![list isKindOfClass:NSArray.class] && ![list isKindOfClass:NSSet.class])) return ((BOOL (*)(id, SEL, id))original)(object, NSSelectorFromString(@"isInRegions:"), list);
                for (id region in list) {
                    if ([region isKindOfClass:NSString.class] && [region caseInsensitiveCompare:iso] == NSOrderedSame) return YES;
                }
                return NO;
            };
        });
        for (NSString *pair in @[@"isRegionInEU:eu", @"isRegionInEEA:eea", @"isRegionInUS:us"]) {
            NSArray *parts = [pair componentsSeparatedByString:@":"];
            NSString *selector = [parts[0] stringByAppendingString:@":"];
            NSSet *set = MTRegionSet(parts[1]);
            SEL sel = NSSelectorFromString(selector);
            ready |= MTHook(@"TIKTOKRegionManager", selector, classMethod.boolValue, "B@:@", ^id(IMP original) {
                return ^BOOL(id object, id region) {
                    if (!enabled) return ((BOOL (*)(id, SEL, id))original)(object, sel, region);
                    NSString *asked = [region isKindOfClass:NSString.class] ? region : iso;
                    return [set containsObject:[asked lowercaseString]];
                };
            });
        }
    }

    // Locale: the language stays, only the country code is spoofed.
    ready |= MTHook(@"NSLocale", @"tspk_network_countryCode", NO, "@@:", ^id(IMP original) {
        return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"tspk_network_countryCode")); };
    });
    ready |= MTHook(@"NSLocale", @"tspk_network_objectForKey:", NO, "@@:@", ^id(IMP original) {
        return ^id(id object, id key) {
            if (enabled && [key isEqual:NSLocaleCountryCode]) return ISO;
            return ((id (*)(id, SEL, id))original)(object, NSSelectorFromString(@"tspk_network_objectForKey:"), key);
        };
    });

    // MCC/MNC per-SDK readers.
    for (NSString *pair in @[@"HMDNetworkHelper:carrierMCC:mcc", @"HMDNetworkHelper:carrierMNC:mnc",
                             @"IESLiveDeviceInfo:carrierMCC:mcc", @"IESLiveDeviceInfo:carrierMNC:mnc",
                             @"IESLiveDeviceInfo:carrierMCCMNC:mccmnc"]) {
        NSArray *parts = [pair componentsSeparatedByString:@":"];
        NSString *value = [parts[2] isEqual:@"mcc"] ? mcc : [parts[2] isEqual:@"mnc"] ? mnc : mccmnc;
        SEL sel = NSSelectorFromString(parts[1]);
        ready |= MTHook(parts[0], parts[1], YES, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? value : ((id (*)(id, SEL))original)(object, sel); };
        });
    }
    ready |= MTHook(@"TMMobileLoginHelper", @"mccmncString", NO, "@@:", ^id(IMP original) {
        return ^id(id object) { return enabled ? mccmnc : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"mccmncString")); };
    });
    ready |= MTHook(@"ACCARFriendEffectViewModel", @"mccmnc", NO, "@@:", ^id(IMP original) {
        return ^id(id object) { return enabled ? mccmnc : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"mccmnc")); };
    });

    // storeRegion on every class that reads it -- the App Store region is what
    // actually steers feed content on iOS.
    for (NSString *owner in @[@"TTKStoreRegionService", @"TTKStoreRegionModel", @"AWESecurity",
                              @"ATSHostEnvImpl", @"ATSNetworkConsumeModel", @"IESForestRequestParameters",
                              @"HybridContext", @"TTKLifeGuardDeviceInfo", @"TTKSADeviceInfoHelpers",
                              @"TikTokEPRDeviceInfoHelpers", @"BDTuringConfigDelegate", @"TSPKDLCCommonSignal",
                              @"TTLHAppBaseInfo", @"LyraxStreamOption"]) {
        ready |= MTHook(owner, @"storeRegion", NO, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"storeRegion")); };
        });
    }
    for (NSString *owner in @[@"PnSPEHostServiceUtil", @"PumbaaProHostValueProvider"]) {
        ready |= MTHook(owner, @"storeRegion", YES, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"storeRegion")); };
        });
    }
    for (NSString *owner in @[@"AWEPassportUtils", @"TTKPassportABTest"]) {
        ready |= MTHook(owner, @"getStoreRegionUpperCase", YES, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"getStoreRegionUpperCase")); };
        });
    }
    for (NSString *owner in @[@"AWEUserService", @"GECUserService", @"GECUserServiceImpl", @"TMUserServiceImp", @"TikTokKidsUserServiceAdaptor"]) {
        ready |= MTHook(owner, @"getStoreRegionUpperCase", NO, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"getStoreRegionUpperCase")); };
        });
    }
    ready |= MTHook(@"TTLHAppBaseInfo", @"carrierRegion", NO, "@@:", ^id(IMP original) {
        return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"carrierRegion")); };
    });
    ready |= MTHook(@"LyraxStreamOption", @"carrierRegion", NO, "@@:", ^id(IMP original) {
        return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"carrierRegion")); };
    });

    // currentRegion reads.
    for (NSString *owner in @[@"ABTestCodeGen", @"AWETrackerInitManager", @"GBLRegionService",
                              @"GBLRegionServiceImpl", @"TTEGKInfoCls", @"AWELiveMTLanguageServiceImpl"]) {
        ready |= MTHook(owner, @"currentRegion", NO, "@@:", ^id(IMP original) {
            return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"currentRegion")); };
        });
    }
    ready |= MTHook(@"TTKABTest", @"currentRegion", YES, "@@:", ^id(IMP original) {
        return ^id(id object) { return enabled ? ISO : ((id (*)(id, SEL))original)(object, NSSelectorFromString(@"currentRegion")); };
    });

    MTCapability(@"region_enabled", ready);
    MTCapability(@"region_country", ready);
}

// Getter only, as on Android (FeedItemList.getItems): the stored list is never
// rewritten, so nothing that indexes it in parallel can go out of step.
static BOOL FeedListHook(NSString *className, NSString *property) {
    SEL get = NSSelectorFromString(property);
    return MTHook(className, property, NO, "@@:", ^id(IMP original) {
        return ^id(id object) {
            id items = ((id (*)(id, SEL))original)(object, get);
            @try { return MTFilterFeed(items); }
            @catch (NSException *exception) {
                MTTrailText([NSString stringWithFormat:@"feed filter threw %@ — %@", exception.name, exception.reason ?: @"?"]);
                return items;
            }
        };
    });
}

// ------------------------------------------------------------ auto-paging
//
// Search and hashtag results come a page at a time, ranked by relevance and
// mostly recent, so a date range or an "only these tags" list can leave a
// page nearly empty. When that happens the next page is requested again, a
// few times, the way scrolling to the bottom would.

static BOOL MTAutoMoreWanted(void) {
    NSArray *tags = MTValue(@"blocked_tags");
    return [MTValue(@"feed_date_from") length] || [MTValue(@"feed_date_to") length]
        || (MTBool(@"only_tags") && [tags isKindOfClass:NSArray.class] && tags.count);
}

static BOOL MTFlag(id object, NSString *name, BOOL fallback) {
    SEL selector = NSSelectorFromString(name);
    return MTMatches(object, selector, "B@:") ? ((BOOL (*)(id, SEL))objc_msgSend)(object, selector) : fallback;
}

static void MTAutoMoreStep(id controller, IMP original, SEL selector, CFAbsoluteTime since, int step) {
    if (!controller || step >= 6 || !MTAutoMoreWanted()) return;
    NSUInteger kept, total;
    CFAbsoluteTime at;
    @synchronized (NSNull.class) { kept = MTLastPage.kept; total = MTLastPage.total; at = MTLastPage.at; }
    if (at < since || !total || kept >= 4) return;
    if (!MTFlag(controller, @"hasMore", YES)) return;
    __weak id weak = controller;
    if (MTFlag(controller, @"isLoadMoreRunning", NO) || MTFlag(controller, @"isLoading", NO)) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MTAutoMoreStep(weak, original, selector, since, step); });
        return;
    }
    MTNote([NSString stringWithFormat:@"auto-more %d: page kept %lu of %lu, loading next (%@)", step + 1, (unsigned long)kept, (unsigned long)total, NSStringFromClass([controller class])]);
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    @try {
        // Our own completion: TikTok's arguments to it, whatever they are, are ignored.
        ((void (*)(id, SEL, id))original)(controller, selector, ^{});
    } @catch (NSException *exception) {
        MTTrailText([NSString stringWithFormat:@"auto-more threw %@ — %@", exception.name, exception.reason ?: @"?"]);
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MTAutoMoreStep(weak, original, selector, now, step + 1); });
}

static BOOL MTAutoMoreHook(NSString *className, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    return MTHook(className, name, NO, "v@:@", ^id(IMP original) {
        return ^(id controller, id completion) {
            CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
            ((void (*)(id, SEL, id))original)(controller, selector, completion);
            if (!MTAutoMoreWanted()) return;
            __weak id weak = controller;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MTAutoMoreStep(weak, original, selector, started, 0); });
        };
    });
}

static BOOL InstallSplash(void) {
    BOOL done = NO;
    for (NSString *selector in @[@"shouldShowAwesomeSplash", @"hasAwesomeSplash", @"isAwesomeSplashShowing"]) {
        SEL sel = NSSelectorFromString(selector);
        done |= MTHook(@"AWEAwesomeSplashManager", selector, NO, "B@:", ^id(IMP original) {
            return ^BOOL(id object) { return MTBool(@"hide_ads") ? NO : ((BOOL (*)(id, SEL))original)(object, sel); };
        });
    }
    done |= MTHook(@"AWEAwesomeSplashManager", @"canShowSplashWithTabType:", NO, "B@:q", ^id(IMP original) {
        return ^BOOL(id object, NSInteger tab) { return MTBool(@"hide_ads") ? NO : ((BOOL (*)(id, SEL, NSInteger))original)(object, NSSelectorFromString(@"canShowSplashWithTabType:"), tab); };
    });
    for (NSString *selector in @[@"showAwesomeSplash", @"prepareForAwesomeSplash"]) {
        SEL sel = NSSelectorFromString(selector);
        done |= MTHook(@"AWEAwesomeSplashManager", selector, NO, "v@:", ^id(IMP original) {
            return ^(id object) { if (!MTBool(@"hide_ads")) ((void (*)(id, SEL))original)(object, sel); };
        });
    }
    done |= MTHook(@"TTKSplashSDKi18NAdapter", @"isAwesomeSplashShowing", NO, "B@:", ^id(IMP original) {
        return ^BOOL(id object) { return MTBool(@"hide_ads") ? NO : ((BOOL (*)(id, SEL))original)(object, NSSelectorFromString(@"isAwesomeSplashShowing")); };
    });
    return done;
}

static BOOL InstallVoiceComments(void) {
    BOOL done = BoolHook(@"ABTestCodeGen", @"audioCommentPublish", @"voice_comments", YES);
    done |= BoolHook(@"TikTokCommentImplGeneratedABTestKeys", @"audioCommentPublish", @"voice_comments", YES);
    BOOL forbid = NO;
    for (NSString *owner in @[@"ABTestCodeGen", @"TikTokCommentImplGeneratedABTestKeys"]) {
        SEL sel = NSSelectorFromString(@"audioCommentPublishEntryForbidden");
        forbid |= MTHook(owner, @"audioCommentPublishEntryForbidden", NO, "B@:", ^id(IMP original) {
            return ^BOOL(id object) { return MTBool(@"voice_comments") ? NO : ((BOOL (*)(id, SEL))original)(object, sel); };
        });
    }
    done |= forbid;
    SEL sel = NSSelectorFromString(@"audioCommentPublish");
    done |= MTHook(@"TTKABTest", @"audioCommentPublish", YES, "B@:", ^id(IMP original) {
        return ^BOOL(id object) { return MTBool(@"voice_comments") ? YES : ((BOOL (*)(id, SEL))original)(object, sel); };
    });
    return done;
}

// No hook: the account is read on the main thread once TikTok is up, and again
// whenever the app comes back.
static BOOL InstallAccount(void) {
    static BOOL scheduled;
    if (!scheduled) {
        scheduled = YES;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MTAccountRemember(); });
    } else if (CFAbsoluteTimeGetCurrent() - MTLaunchTime > 15) {
        MTAccountRemember();
    }
    return NSClassFromString(@"AWEUserService") != nil;
}

@interface MTLagWatch : NSObject
@property (nonatomic, assign) CFTimeInterval previous;
@property (nonatomic, assign) NSUInteger reported;
- (void)tick:(CADisplayLink *)link;
@end
@implementation MTLagWatch
- (void)tick:(CADisplayLink *)link {
    CFTimeInterval now = link.timestamp;
    if (self.previous > 0 && self.reported < 10) {
        CFTimeInterval gap = now - self.previous - link.duration;
        if (gap > 0.7) {
            self.reported++;
            MTNote([NSString stringWithFormat:@"lag: main thread stalled %.0f ms", gap * 1000]);
        }
    }
    self.previous = now;
}
@end

void MTInstallHooks(void) {
    static int installs;
    BOOL first = installs++ == 0;
    void (^stage)(NSString *) = ^(NSString *name) { if (first) MTTrailText([@"stage " stringByAppendingString:name]); };
    stage(@"entries");
    InstallEntries();
    stage(@"region");
    InstallRegion();
    stage(@"account");
    MTCapability(@"account_id", InstallAccount());
    static MTLagWatch *lagWatch;
    if (!lagWatch) {
        lagWatch = [MTLagWatch new];
        CADisplayLink *timer = [CADisplayLink displayLinkWithTarget:lagWatch selector:@selector(tick:)];
        [timer addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    stage(@"feed");
    BOOL feed = NO;
    // For You (AWEAwemeResponseModel, handed to the feed service as
    // TTKFeedDataResponseResult), the other feed tabs, search videos and
    // hashtag pages. Getters only.
    for (NSString *owner in @[@"AWEAwemeResponseModel", @"TTKFeedDataResponseResult", @"TTKFeedBaseResponseModel",
                              @"TTKSearchAwemePoolDataController", @"AWEChallengeAwemeListResponse"]) feed |= FeedListHook(owner, @"awemeList");
    feed |= FeedListHook(@"TTKSearchAwemeResponse", @"awemes");
    stage(@"auto-more");
    for (NSString *owner in @[@"AWESearchVideoListDataViewController", @"TikTokSearchVideoListSyncDataController",
                              @"TTKSearchAwemePoolDataController", @"TTKSearchMultiVideoInnerDataController"]) MTAutoMoreHook(owner, @"loadMoreWithCompletion:");
    for (NSString *owner in @[@"AWEChallengeAwemeListDataController"]) MTAutoMoreHook(owner, @"loadMoreWithFilteredCompletion:");
    stage(@"splash");
    InstallSplash();
    stage(@"voice");
    MTCapability(@"voice_comments", InstallVoiceComments());
    MTCapability(@"update_check", YES);
    stage(@"video");
    for (NSString *key in @[@"hide_ads", @"hide_live", @"hide_photos", @"blocked_tags", @"blocked_tags_on", @"only_tags", @"feed_date_from", @"feed_date_to", @"hide_soft_ads", @"hide_commission", @"hide_sensitive", @"hide_warnings", @"hide_recommendations", @"hide_popups", @"hide_shop", @"hide_location_ads", @"hide_insert_cards", @"hide_ai"]) MTCapability(key, feed);
    BOOL seekbar = BoolHook(@"AWEAwemeModel", @"progressBarVisible", @"seekbar_always", YES);
    seekbar &= BoolHook(@"AWEAwemeModel", @"progressBarDraggable", @"seekbar_always", YES);
    MTCapability(@"seekbar_always", seekbar);
    MTCapability(@"always_date", BoolHook(@"AWEPlayInteractionAuthorElement", @"shouldShowTimeStampLabel", @"always_date", YES));
    BOOL sound = BoolHook(@"AWEAwemeModel", @"musicIsMuted", @"sound_available", NO);
    sound |= BoolHook(@"AWEAwemeModel", @"musicIsMutedDueToCopyrightViolation", @"sound_available", NO);
    BoolHook(@"AWEMusicModel", @"shouldMuteShare", @"sound_available", NO);
    MTCapability(@"sound_available", sound);
    stage(@"downloads");
    BOOL downloads = URLHook(@"AWEVideoModel", @"downloadURL", @[@"downloadNoWatermarkURL", @"playURL"]);
    downloads |= BoolHook(@"AWEAwemeModel", @"allowDownloadWithoutWatermark", @"download_no_watermark", YES);
    downloads |= BoolHook(@"AWEAwemeModel", @"shouldAddCreatorTTSWatermarkWhenDownloading", @"download_no_watermark", NO);
    URLHook(@"AWEVideoModel", @"h264DownloadURL", @[@"downloadNoWatermarkURL", @"playURL"]);
    URLHook(@"AWEPhotoAlbumPhoto", @"ownerWatermarkedPhotoURL", @[@"originPhotoURL"]);
    URLHook(@"AWEPhotoAlbumPhoto", @"userWatermarkedPhotoURL", @[@"originPhotoURL"]);
    MTCapability(@"download_no_watermark", downloads);
    MTCapability(@"download_button", InstallDownloadButton());
    BOOL save = BoolHook(@"AWEAwemeModel", @"preventDownload", @"download_always", NO);
    BoolHook(@"AWEAwemeModel", @"disableDownload", @"download_always", NO);
    BoolHook(@"AWEUserModel", @"preventDownload", @"download_always", NO);
    save |= BoolHook(@"VideoControl", @"allowDownload", @"download_always", YES);
    save |= BoolHook(@"VideoControlV", @"allowDownload", @"download_always", YES);
    save |= BoolHook(@"AWELongVideoControlModel", @"allowDownload", @"download_always", YES);
    save |= BoolHook(@"AWECommerceCardStruct", @"disableDownload", @"download_always", NO);
    MTCapability(@"download_always", save);
    MTCapability(@"no_hdr", BoolHook(@"AWEAwemeModel", @"enableHDR", @"no_hdr", NO));
    stage(@"appearance");
    MTInstallAppearance();
}

// ---------------------------------------------------------------- crash trail
//
// Everything below survives any kind of process death: the trail is a plain
// file written with write()+fsync, the signal handler only uses
// async-signal-safe calls, and the launch marker counts a launch as crashed
// whenever it did not live long enough to remove it -- which also catches
// watchdog kills and crashes swallowed by TikTok's own crash reporter.

static NSUncaughtExceptionHandler *MTPreviousHandler;

static void MTCrash(NSException *exception) {
    MTTrailText([NSString stringWithFormat:@"CRASH exception %@ — %@\n%@", exception.name, exception.reason ?: @"?", [exception.callStackSymbols componentsJoinedByString:@"\n"]]);
    if (MTPreviousHandler) MTPreviousHandler(exception);
}

static void MTSignal(int sig) {
    static volatile sig_atomic_t handling;
    int fd = MTTrailFD;
    if (!handling && fd >= 0) {
        handling = 1;
        const char *name = sig == SIGSEGV ? "SIGSEGV" : sig == SIGBUS ? "SIGBUS" : sig == SIGABRT ? "SIGABRT"
                         : sig == SIGILL ? "SIGILL" : sig == SIGTRAP ? "SIGTRAP" : "SIGFPE";
        (void)write(fd, "CRASH signal ", 13);
        (void)write(fd, name, strlen(name));
        (void)write(fd, "\n", 1);
        void *frames[64];
        int count = backtrace(frames, 64);
        backtrace_symbols_fd(frames, count, fd);
        fsync(fd);
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

// TikTok installs its own crash reporter after launch and takes the handlers
// over, so ours are re-armed a few times; the previous exception handler is
// still called afterwards.
static void MTArmCrashHandlers(void) {
    NSUncaughtExceptionHandler *current = NSGetUncaughtExceptionHandler();
    if (current != MTCrash) {
        MTPreviousHandler = current;
        NSSetUncaughtExceptionHandler(MTCrash);
    }
    const int sigs[] = {SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE};
    for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) signal(sigs[i], MTSignal);
}

// Returns how many launches in a row died before surviving.
static NSInteger MTBoot(void) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *marker = MTSupportPath(@"launch.marker"), *log = MTSupportPath(@"crash.log"), *last = MTSupportPath(@"crash-last.log");
    NSString *previous = [NSString stringWithContentsOfFile:marker encoding:NSUTF8StringEncoding error:nil];
    NSInteger streak = previous ? previous.integerValue + 1 : 0;
    if (previous) {
        [files removeItemAtPath:last error:nil];
        [files moveItemAtPath:log toPath:last error:nil];
    } else {
        [files removeItemAtPath:log error:nil];
    }
    [[NSString stringWithFormat:@"%ld", (long)streak] writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
    MTTrailFD = open(log.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    return streak;
}

static void MTSurvived(void) {
    static BOOL done;
    if (done) return;
    done = YES;
    [NSFileManager.defaultManager removeItemAtPath:MTSupportPath(@"launch.marker") error:nil];
    MTTrail("survived");
}

__attribute__((constructor)) static void MTStart(void) {
    @autoreleasepool {
        NSBundle *bundle = NSBundle.mainBundle;
        if (![[bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"TikTok"] || ![bundle.bundlePath.pathExtension isEqual:@"app"]) return;
        if (![[bundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] isEqual:@"46.9.0"]) return;
        MTLaunchTime = CFAbsoluteTimeGetCurrent();
        NSInteger streak = MTBoot();
        MTArmCrashHandlers();
        // 0-1 crashes: everything. 2-3 in a row: only the menu entry, so the
        // diagnostics can be read. 4+: nothing at all, to tell a bad hook from
        // a bad IPA.
        NSString *mode = streak >= 4 ? @"off" : streak >= 2 ? @"minimal" : @"full";
        MTTrailText([NSString stringWithFormat:@"launch %@ build %@ streak %ld mode %@", MTVersion, [bundle objectForInfoDictionaryKey:@"CFBundleVersion"], (long)streak, mode]);
        MTNote([NSString stringWithFormat:@"Starting MargyT %@ (%@ mode, %ld crashed launches before)", MTVersion, mode, (long)streak]);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ MTSurvived(); });
        [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { MTSurvived(); }];
        if ([mode isEqual:@"off"]) return;
        BOOL minimal = [mode isEqual:@"minimal"];
        if (!minimal) {
            MTTrail("stage region");
            InstallRegion();
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MTArmCrashHandlers();
            @try {
                if (minimal) { MTTrail("stage entries"); InstallEntries(); }
                else MTInstallHooks();
                MTTrail("hooks installed");
            } @catch (NSException *exception) {
                MTTrailText([NSString stringWithFormat:@"install failed: %@ — %@", exception.name, exception.reason ?: @"?"]);
            }
            for (int64_t delay = 3; delay <= 12; delay += 3) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, delay * (int64_t)NSEC_PER_SEC), dispatch_get_main_queue(), ^{ MTArmCrashHandlers(); });
            }
            if (!minimal) [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) { MTInstallHooks(); }];
        });
    }
}
