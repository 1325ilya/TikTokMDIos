#import "MTCore.h"

NSString *const MTSettingsChanged = @"cat.narezany.margyt.settingsChanged";

NSString *MTText(NSString *russian, NSString *english) {
    NSString *language = NSLocale.preferredLanguages.firstObject.lowercaseString;
    return [language hasPrefix:@"ru"] || [language hasPrefix:@"be"] ? russian : english;
}

static NSDictionary *Row(NSString *key, NSString *title, NSString *detail,
                         NSString *symbol, NSString *kind, id value, NSArray *choices) {
    return @{@"key": key, @"title": title, @"detail": detail, @"symbol": symbol,
             @"kind": kind, @"default": value, @"choices": choices ?: @[]};
}

NSArray<NSDictionary *> *MTSections(void) {
    static NSArray *sections;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sections = @[
            @{@"title": MTText(@"Меню", @"Menu"), @"rows": @[
                Row(@"live_menu", MTText(@"LIVE открывает MargyT", @"Open MargyT with LIVE"), MTText(@"Отключите, чтобы вернуть обычную кнопку эфиров. Вход из настроек остаётся.", @"Turn off to restore LIVE. Settings access remains available."), @"dot.radiowaves.left.and.right", @"toggle", @YES, nil),
                Row(@"menu_style", MTText(@"Оформление меню", @"Menu appearance"), MTText(@"Системная, светлая или тёмная тема", @"System, light or dark appearance"), @"circle.lefthalf.filled", @"choice", @"system", @[@[@"system", MTText(@"Как в системе", @"System")], @[@"light", MTText(@"Светлая", @"Light")], @[@"dark", MTText(@"Тёмная", @"Dark")]]),
                Row(@"menu_accent", MTText(@"Акцент меню", @"Menu accent"), MTText(@"Цвет интерфейса MargyT, не всего TikTok", @"MargyT interface colour, not all of TikTok"), @"paintpalette", @"choice", @"8DD1B0", @[@[@"8DD1B0", MTText(@"Мята", @"Mint")], @[@"4C8DFF", MTText(@"Синий", @"Blue")], @[@"9B6BFF", MTText(@"Фиолетовый", @"Violet")], @[@"FE2C55", MTText(@"Розовый", @"Pink")]])
            ]},
            @{@"title": MTText(@"Регион", @"Region"), @"rows": @[
                Row(@"region_enabled", MTText(@"Менять регион", @"Change region"), MTText(@"После перезапуска. Не меняет IP, язык и регион аккаунта на сервере. CoreTelephony может не использоваться новыми версиями iOS.", @"Restart required. Does not change IP, language or server account region. New iOS versions may not use CoreTelephony."), @"globe", @"toggle", @YES, nil),
                Row(@"region_country", MTText(@"Страна", @"Country"), MTText(@"Тот же список стран и операторов, что на Android", @"The same countries and carriers as on Android"), @"location", @"country", @"nl", nil)
            ]},
            @{@"title": MTText(@"Лента", @"Feed"), @"rows": @[
                Row(@"hide_ads", MTText(@"Убирать рекламу из ленты", @"Remove feed ads"), MTText(@"Фильтрует посты с рекламной меткой, не заставки и не Shop", @"Filters posts marked as ads, not splash ads or Shop"), @"hand.raised", @"toggle", @NO, nil),
                Row(@"hide_live", MTText(@"Скрывать трансляции", @"Hide live rooms"), @"", @"video.slash", @"toggle", @NO, nil),
                Row(@"hide_photos", MTText(@"Скрывать фото-посты", @"Hide photo posts"), MTText(@"Свои посты не скрываются при доступном ID аккаунта", @"Own posts are preserved when the account ID is available"), @"photo.on.rectangle", @"toggle", @NO, nil),
                Row(@"blocked_tags_on", MTText(@"Фильтровать хештеги", @"Filter hashtags"), MTText(@"Совпадение целого хештега, без учёта регистра", @"Whole hashtag matching, case insensitive"), @"number", @"toggle", @YES, nil),
                Row(@"blocked_tags", MTText(@"Список хештегов", @"Blocked hashtags"), MTText(@"До 40 тегов, через запятую", @"Up to 40 tags, comma separated"), @"text.badge.minus", @"tags", @[], nil),
                Row(@"feed_date_from", MTText(@"Посты не раньше", @"Posts not before"), MTText(@"Дата ГГГГ-ММ-ДД или пусто. Работает в ленте и в поиске.", @"YYYY-MM-DD or empty. Works in feed and search."), @"calendar.badge.clock", @"date", @"", nil),
                Row(@"feed_date_to", MTText(@"Посты не позже", @"Posts not after"), MTText(@"Дата ГГГГ-ММ-ДД или пусто", @"YYYY-MM-DD or empty"), @"calendar", @"date", @"", nil)
            ]},
            @{@"title": MTText(@"Видео", @"Video"), @"rows": @[
                Row(@"sound_available", MTText(@"Не заглушать доступную дорожку", @"Keep available audio unmuted"), MTText(@"Только локальное заглушение. Удалённый сервером звук не восстанавливается.", @"Local muting only. Cannot restore audio removed by the server."), @"speaker.wave.2", @"toggle", @YES, nil),
                Row(@"seekbar_always", MTText(@"Перемотка на всех видео", @"Always show the scrubber"), @"", @"slider.horizontal.3", @"toggle", @NO, nil),
                Row(@"always_date", MTText(@"Дата под видео", @"Show post dates"), @"", @"calendar", @"toggle", @NO, nil),
                Row(@"dim_on", MTText(@"Приглушать элементы над видео", @"Dim video controls"), MTText(@"Снижает яркость неподвижных элементов, но не гарантирует защиту OLED", @"Dims static controls; does not guarantee OLED burn-in protection"), @"sun.min", @"toggle", @NO, nil),
                Row(@"dim_how", MTText(@"Приглушение", @"Dimming"), @"", @"sun.max", @"choice", @35, @[@[@20, @"20%"], @[@35, @"35%"], @[@50, @"50%"], @[@70, @"70%"], @[@90, @"90%"]]),
                Row(@"no_hdr", MTText(@"Не включать HDR", @"Disable HDR requests"), MTText(@"Отключает флаг HDR модели TikTok. Не является преобразованием видео в SDR; нужен перезапуск.", @"Disables TikTok's model HDR flag, not video-to-SDR conversion. Restart required."), @"sparkles.tv", @"toggle", @NO, nil),
                Row(@"fps_lock", MTText(@"Частота интерфейса", @"Interface frame rate"), MTText(@"Запрос CADisplayLink, в пределах экрана. iOS может снизить частоту; FPS видео не меняется. После перезапуска.", @"Requests CADisplayLink rates within display limits. iOS may lower them; video FPS is unchanged. Restart required."), @"speedometer", @"choice", @0, @[@[@0, MTText(@"Автоматически", @"Automatic")], @[@60, @"60 Hz"], @[@90, @"90 Hz"], @[@120, @"120 Hz"]])
            ]},
            @{@"title": MTText(@"Сохранение", @"Saving"), @"rows": @[
                Row(@"download_no_watermark", MTText(@"Без водяного знака", @"Without watermarks"), MTText(@"Чистый URL видео и фото, если он есть в модели; иначе оригинал", @"Uses clean video/photo URLs when present; otherwise preserves the original"), @"drop.slash", @"toggle", @NO, nil),
                Row(@"download_always", MTText(@"Разрешать сохранение в интерфейсе", @"Enable local save controls"), MTText(@"Не даёт доступа к закрытому контенту и не меняет серверные разрешения", @"Does not grant access to private content or change server permissions"), @"square.and.arrow.down", @"toggle", @NO, nil),
                Row(@"save_avatars", MTText(@"Поделиться аватаром", @"Share an avatar"), MTText(@"Удерживайте открытый аватар: системное меню сохранения показанного изображения", @"Hold an open avatar to save/share the displayed image"), @"person.crop.circle", @"toggle", @YES, nil),
                Row(@"save_stickers", MTText(@"Поделиться стикером комментария", @"Share a comment sticker"), MTText(@"Удерживайте превью. Сохраняет показанный кадр, не исходную анимацию и не стикеры переписки.", @"Hold the preview. Shares the displayed frame, not the original animation or chat stickers."), @"face.smiling", @"toggle", @YES, nil),
                Row(@"download_button", MTText(@"Кнопка скачивания в ленте", @"Feed download button"), MTText(@"Добавляет кнопку над действиями справа: видео .mp4 и фото без водяного знака, в галерею или в меню «Поделиться»", @"Adds a button above the right action bar: watermark-free .mp4 video and photos, to Photos or the share sheet"), @"arrow.down.circle", @"toggle", @YES, nil),
                Row(@"save_comment_media", MTText(@"Сохранять фото из комментариев", @"Save comment photos"), MTText(@"Удерживайте фото в комментариях. Сохраняется показанное изображение; вотермарка, вшитая автором, остаётся.", @"Hold a comment photo. Saves the displayed image; uploader-baked watermarks remain."), @"photo.badge.arrow.down", @"toggle", @YES, nil)
            ]},
            @{@"title": MTText(@"Типографика", @"Typography"), @"rows": @[
                Row(@"font", MTText(@"Шрифт TikTok", @"TikTok typeface"), MTText(@"Только TUXLabel; новые надписи после смены. Размер и начертание сохраняются, где возможно.", @"TUXLabel only; newly configured labels. Keeps size and weight where possible."), @"textformat", @"choice", @"system", @[@[@"system", MTText(@"Оригинальный", @"Original")], @[@"rounded", MTText(@"Закруглённый", @"Rounded")], @[@"serif", MTText(@"С засечками", @"Serif")], @[@"monospaced", MTText(@"Моноширинный", @"Monospaced")]])
            ]},
            @{@"title": MTText(@"Ещё не перенесено", @"Not yet ported"), @"rows": @[
                Row(@"pending_appearance", MTText(@"Темы, текстурпаки, иконки и шрифты из файлов", @"Themes, textures, icons and custom font files"), MTText(@"Android-ресурсы не совместимы с UIKit/Assets.car. Полная перекраска TikTok и замена эмодзи пока не перенесены.", @"Android resources are incompatible with UIKit/Assets.car. App-wide colours and emoji replacement are not ported yet."), @"paintbrush", @"info", @NO, nil),
                Row(@"pending_server", MTText(@"Значки, градиенты и баннеры", @"Badges, gradients and banners"), MTText(@"Нужны iOS-привязки профиля и HTTPS на сервере. Токены через HTTP не отправляются.", @"Requires iOS profile bindings and an HTTPS server. Tokens are not sent over HTTP."), @"person.crop.rectangle", @"info", @NO, nil),
                Row(@"pending_plugins", MTText(@"Плагины и заплатки", @"Plugins and patches"), MTText(@".mtp/classes.dex и Android-заплатки не исполняются на iOS. Нужны отдельный API и подписанные iOS-пакеты.", @"Android .mtp/classes.dex and patches cannot execute on iOS. A separate API and signed iOS packages are required."), @"puzzlepiece.extension", @"info", @NO, nil),
                Row(@"pending_streaks", MTText(@"Автосерии и голосовые комментарии", @"Automatic streaks and voice comments"), MTText(@"iOS-контракты не проверены. Автоматические сообщения не отправляются.", @"iOS contracts have not been verified. No automatic messages are sent."), @"bubble.left.and.bubble.right", @"info", @NO, nil),
                Row(@"pending_downloads", MTText(@"Стикеры чата и анимации комментариев", @"Chat stickers and comment animations"), MTText(@"Оригинальные анимированные файлы требуют отдельных iOS-обработчиков.", @"Original animated files need separate iOS handlers."), @"photo", @"info", @NO, nil),
                Row(@"pending_updates", MTText(@"Обновления и пасхалка", @"Updates and Easter egg"), MTText(@"Android APK не предлагается как обновление iOS. Для обновлений нужен отдельный IPA-канал; пасхалка пока не перенесена.", @"Android APKs are not offered as iOS updates. Updates need a separate IPA channel; the Easter egg is not ported yet."), @"arrow.triangle.2.circlepath", @"info", @NO, nil)
            ]},
            @{@"title": MTText(@"Диагностика", @"Diagnostics"), @"rows": @[
                Row(@"diagnostics", MTText(@"Совместимость и журнал", @"Compatibility and log"), MTText(@"Установленные обработчики не означают проверку на устройстве", @"Installed hooks do not imply on-device verification"), @"stethoscope", @"diagnostics", @NO, nil)
            ]}
        ];
    });
    return sections;
}

@interface MTState : NSObject
@property (atomic, copy) NSDictionary *values;
@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSMutableSet *capabilities;
@property (nonatomic, strong) NSMutableSet *hooks;
@property (nonatomic, strong) NSMutableArray *log;
+ (instancetype)shared;
@end

@implementation MTState
+ (instancetype)shared {
    static MTState *state;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        state = [MTState new];
        state.defaults = [[NSUserDefaults alloc] initWithSuiteName:@"cat.narezany.margyt.ios"];
        NSMutableDictionary *values = [NSMutableDictionary dictionary];
        for (NSDictionary *section in MTSections()) {
            for (NSDictionary *row in section[@"rows"]) {
                id saved = [state.defaults objectForKey:row[@"key"]];
                id fallback = row[@"default"];
                values[row[@"key"]] = [saved isKindOfClass:[fallback isKindOfClass:NSNumber.class] ? NSNumber.class : [fallback isKindOfClass:NSArray.class] ? NSArray.class : NSString.class] ? saved : fallback;
            }
        }
        state.values = values;
        state.capabilities = [NSMutableSet setWithArray:@[@"menu_style", @"menu_accent"]];
        state.hooks = [NSMutableSet set];
        state.log = [[state.defaults stringArrayForKey:@"diary"] mutableCopy] ?: [NSMutableArray array];
    });
    return state;
}
@end

id MTValue(NSString *key) { return MTState.shared.values[key]; }
BOOL MTBool(NSString *key) { return [MTValue(key) boolValue]; }

NSArray<NSDictionary *> *MTCountries(void) {
    static NSArray *countries;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"MargyT.bundle/Countries.plist"];
        countries = [NSArray arrayWithContentsOfFile:path];
        if (!countries.count) countries = @[@{@"iso": @"nl", @"mcc": @"204", @"mnc": @"08", @"carrier": @"KPN", @"name": @"Netherlands"}];
    });
    return countries;
}

NSDictionary *MTCountry(void) {
    for (NSDictionary *country in MTCountries()) if ([country[@"iso"] isEqual:MTValue(@"region_country")]) return country;
    return MTCountries().firstObject;
}

BOOL MTSet(NSString *key, id value) {
    NSDictionary *definition;
    for (NSDictionary *section in MTSections()) for (NSDictionary *row in section[@"rows"]) if ([row[@"key"] isEqual:key]) definition = row;
    NSString *kind = definition[@"kind"];
    if (!kind || [kind isEqual:@"info"] || [kind isEqual:@"diagnostics"]) return NO;
    if ([kind isEqual:@"toggle"] && (![value isKindOfClass:NSNumber.class] || ![@[@0, @1] containsObject:value])) return NO;
    if ([kind isEqual:@"choice"] && ![[definition[@"choices"] valueForKey:@"firstObject"] containsObject:value]) return NO;
    if ([kind isEqual:@"country"] && ![[MTCountries() valueForKey:@"iso"] containsObject:value]) return NO;
    if ([kind isEqual:@"tags"]) {
        if (![value isKindOfClass:NSArray.class] || [value count] > 40) return NO;
        NSMutableOrderedSet *clean = [NSMutableOrderedSet orderedSet];
        NSCharacterSet *letters = [NSCharacterSet characterSetWithCharactersInString:@"_"].mutableCopy;
        [(NSMutableCharacterSet *)letters formUnionWithCharacterSet:NSCharacterSet.alphanumericCharacterSet];
        for (id item in value) {
            if (![item isKindOfClass:NSString.class]) return NO;
            NSString *tag = [[item stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
            while ([tag hasPrefix:@"#"]) tag = [tag substringFromIndex:1];
            if (!tag.length) continue;
            if (tag.length > 100 || [tag rangeOfCharacterFromSet:letters.invertedSet].location != NSNotFound) return NO;
            [clean addObject:tag];
        }
        value = clean.array;
    }
    if ([kind isEqual:@"date"]) {
        if (![value isKindOfClass:NSString.class]) return NO;
        if ([value length]) {
            NSDateFormatter *formatter = [NSDateFormatter new];
            formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
            formatter.dateFormat = @"yyyy-MM-dd";
            formatter.lenient = NO;
            if (![formatter dateFromString:value]) return NO;
        }
    }
    MTState *state = MTState.shared;
    @synchronized (state) {
        NSMutableDictionary *values = state.values.mutableCopy;
        values[key] = value;
        [state.defaults setObject:value forKey:key];
        state.values = values;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [NSNotificationCenter.defaultCenter postNotificationName:MTSettingsChanged object:nil];
    });
    return YES;
}

UIColor *MTColor(NSString *hex) {
    unsigned int value = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&value];
    return [UIColor colorWithRed:((value >> 16) & 255) / 255.0 green:((value >> 8) & 255) / 255.0 blue:(value & 255) / 255.0 alpha:1];
}
UIColor *MTAccent(void) {
    UIColor *base = MTColor(MTValue(@"menu_accent"));
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        if (traits.userInterfaceStyle == UIUserInterfaceStyleDark) return base;
        CGFloat hue = 0, saturation = 0, brightness = 0, alpha = 1;
        [base getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
        return [UIColor colorWithHue:hue saturation:MAX(saturation, 0.6) brightness:MIN(brightness, 0.48) alpha:alpha];
    }];
}

void MTNote(NSString *message) {
    MTState *state = MTState.shared;
    @synchronized (state) {
        [state.log addObject:[NSString stringWithFormat:@"%@  %@", NSDate.date, message]];
        if (state.log.count > 80) [state.log removeObjectsInRange:NSMakeRange(0, state.log.count - 80)];
        [state.defaults setObject:state.log forKey:@"diary"];
    }
}
void MTCapability(NSString *key, BOOL ready) {
    if (!ready) return;
    MTState *state = MTState.shared;
    @synchronized (state) { [state.capabilities addObject:key]; }
}
BOOL MTAvailable(NSString *key) {
    MTState *state = MTState.shared;
    @synchronized (state) { return [state.capabilities containsObject:key]; }
}
NSString *MTDiagnostics(void) {
    MTState *state = MTState.shared;
    @synchronized (state) {
        return [NSString stringWithFormat:@"MargyT iOS — development port\nTikTok %@ (%@)\niOS %@\n\n%@\n\n%@",
                [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?",
                [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"?",
                UIDevice.currentDevice.systemVersion,
                MTText(@"Проверка на устройстве не выполнена. Совместимость с iOS 27 не подтверждена.\nЖурнал не содержит токенов и содержимого сообщений.", @"Not verified on a device. iOS 27 compatibility is unconfirmed.\nNo tokens or message contents are logged."),
                [state.log componentsJoinedByString:@"\n"]];
    }
}

static char Type(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return *type == 'c' ? 'B' : *type;
}
BOOL MTMatches(id object, SEL selector, const char *signature) {
    if (!object || ![object respondsToSelector:selector]) return NO;
    NSMethodSignature *method = [object methodSignatureForSelector:selector];
    if (!method || strlen(signature) != method.numberOfArguments + 1 || Type(method.methodReturnType) != signature[0]) return NO;
    for (NSUInteger i = 0; i < method.numberOfArguments; i++) if (Type([method getArgumentTypeAtIndex:i]) != signature[i + 1]) return NO;
    return YES;
}
id MTGet(id object, NSString *selector) {
    SEL sel = NSSelectorFromString(selector);
    if (!MTMatches(object, sel, "@@:")) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, sel);
}
BOOL MTHook(NSString *className, NSString *selector, BOOL classMethod,
            const char *signature, id (^makeBlock)(IMP)) {
    MTState *state = MTState.shared;
    NSString *key = [NSString stringWithFormat:@"%@[%@ %@]", classMethod ? @"+" : @"-", className, selector];
    @synchronized (state) {
        if ([state.hooks containsObject:key]) return YES;
        Class target = NSClassFromString(className);
        Class cls = classMethod ? object_getClass(target) : target;
        SEL sel = NSSelectorFromString(selector);
        Method method = cls ? class_getInstanceMethod(cls, sel) : NULL;
        if (!method) return NO;
        NSMethodSignature *actual = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (actual.numberOfArguments + 1 != strlen(signature) || Type(actual.methodReturnType) != signature[0]) return NO;
        for (NSUInteger i = 0; i < actual.numberOfArguments; i++) if (Type([actual getArgumentTypeAtIndex:i]) != signature[i + 1]) return NO;
        IMP replacement = imp_implementationWithBlock(makeBlock(method_getImplementation(method)));
        if (!class_addMethod(cls, sel, replacement, method_getTypeEncoding(method))) method_setImplementation(class_getInstanceMethod(cls, sel), replacement);
        [state.hooks addObject:key];
        MTNote([@"Hook installed: " stringByAppendingString:key]);
        return YES;
    }
}
