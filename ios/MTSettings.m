#import "MTCore.h"

UIWindow *MTActiveWindow(void) {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive || ![scene isKindOfClass:UIWindowScene.class]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow && !window.hidden) return window;
    }
    return nil;
}
UIViewController *MTTopController(UIWindow *window) {
    UIViewController *controller = window.rootViewController;
    for (NSUInteger depth = 0; controller && depth < 30; depth++) {
        if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) controller = controller.presentedViewController;
        else if ([controller isKindOfClass:UINavigationController.class]) controller = ((UINavigationController *)controller).visibleViewController;
        else if ([controller isKindOfClass:UITabBarController.class]) controller = ((UITabBarController *)controller).selectedViewController;
        else break;
    }
    return controller;
}
void MTShowMessage(UIViewController *presenter, NSString *title, NSString *message) {
    if (!presenter || presenter.presentedViewController || !presenter.view.window) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:MTText(@"Понятно", @"OK") style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
}

static UIVisualEffect *Glass(void) {
    if (UIAccessibilityIsReduceTransparencyEnabled()) return nil;
    Class glass = NSClassFromString(@"UIGlassEffect");
    SEL factory = NSSelectorFromString(@"effectWithStyle:");
    if (MTMatches(glass, factory, "@@:q")) return ((id (*)(id, SEL, NSInteger))objc_msgSend)(glass, factory, 0);
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
}

@interface MTChoiceController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSString *key;
@property (nonatomic, copy) NSArray *choices;
@property (nonatomic, copy) NSArray *visible;
@property (nonatomic, strong) UISearchController *search;
@end

@implementation MTChoiceController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.visible = self.choices;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 60;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.navigationItem.searchController = self.search;
    self.definesPresentationContext = YES;
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    self.visible = !query.length ? self.choices : [self.choices filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSArray *choice, NSDictionary *bindings) {
        return [[NSString stringWithFormat:@"%@ %@ %@", choice[0], choice[1], choice.count > 2 ? choice[2] : @""] localizedStandardContainsString:query];
    }]];
    [self.tableView reloadData];
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.visible.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.row >= (NSInteger)self.visible.count) return cell;
    NSArray *choice = self.visible[indexPath.row];
    if (choice.count < 2) return cell;
    cell.textLabel.text = choice[1];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = choice.count > 2 ? choice[2] : nil;
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.accessoryType = [choice[0] isEqual:MTValue(self.key)] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
    cell.tintColor = MTAccent();
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= (NSInteger)self.visible.count) return;
    if (MTSet(self.key, self.visible[indexPath.row][0])) {
        [self.tableView reloadData];
        [self.navigationController popViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled()];
    }
}
@end

@interface MTLogController : UIViewController
@end
@implementation MTLogController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = MTText(@"Диагностика", @"Diagnostics");
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    UITextView *text = [UITextView new];
    text.translatesAutoresizingMaskIntoConstraints = NO;
    text.editable = NO;
    text.text = MTDiagnostics();
    text.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody] scaledFontForFont:[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular]];
    text.adjustsFontForContentSizeCategory = YES;
    text.textContainerInset = UIEdgeInsetsMake(16, 16, 16, 16);
    [self.view addSubview:text];
    [NSLayoutConstraint activateConstraints:@[
        [text.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [text.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],
        [text.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [text.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:MTText(@"Копировать", @"Copy") style:UIBarButtonItemStylePlain target:self action:@selector(copyLog)];
}
- (void)copyLog { UIPasteboard.generalPasteboard.string = MTDiagnostics(); }
@end

@interface MTSettingsController : UITableViewController <UISearchResultsUpdating>
@property (nonatomic, copy) NSArray *sections;
@property (nonatomic, strong) UISearchController *search;
@property (nonatomic, strong) UIView *hero;
@property (nonatomic, strong) UIVisualEffectView *glass;
@property (nonatomic, assign) CGFloat heroWidth;
@end

@implementation MTSettingsController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"MargyT";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(close)];
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 88;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.searchResultsUpdater = self;
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchBar.placeholder = MTText(@"Поиск настроек", @"Search settings");
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self buildHero];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:MTSettingsChanged object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(refresh) name:UIAccessibilityReduceTransparencyStatusDidChangeNotification object:nil];
    [self refresh];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
- (void)close { [self.navigationController dismissViewControllerAnimated:!UIAccessibilityIsReduceMotionEnabled() completion:nil]; }
- (void)buildHero {
    self.hero = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 360, 180)];
    self.glass = [[UIVisualEffectView alloc] initWithEffect:Glass()];
    self.glass.translatesAutoresizingMaskIntoConstraints = NO;
    self.glass.layer.cornerRadius = 26;
    self.glass.layer.cornerCurve = kCACornerCurveContinuous;
    self.glass.clipsToBounds = YES;
    [self.hero addSubview:self.glass];
    UIImageView *symbol = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"slider.horizontal.3" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:32 weight:UIImageSymbolWeightSemibold]]];
    symbol.contentMode = UIViewContentModeScaleAspectFit;
    symbol.isAccessibilityElement = NO;
    UILabel *title = [UILabel new];
    title.text = MTText(@"Твой TikTok. Твои настройки.", @"Your TikTok. Your settings.");
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleTitle2];
    title.numberOfLines = 0;
    title.adjustsFontForContentSizeCategory = YES;
    title.userInteractionEnabled = YES;
    [title addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(catTapped:)]];
    UILabel *detail = [UILabel new];
    detail.text = [NSString stringWithFormat:@"%@\n%@ · TikTok %@",
                   MTText(@"Нативный интерфейс iOS", @"Native iOS interface"),
                   [NSString stringWithFormat:MTText(@"MargyT iOS %@ — экспериментальный перенос", @"MargyT iOS %@ — experimental port"), MTVersion],
                   [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"46.9.0"];
    detail.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    detail.textColor = UIColor.secondaryLabelColor;
    detail.numberOfLines = 0;
    detail.adjustsFontForContentSizeCategory = YES;
    UIStackView *words = [[UIStackView alloc] initWithArrangedSubviews:@[title, detail]];
    words.axis = UILayoutConstraintAxisVertical;
    words.spacing = 8;
    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[symbol, words]];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 18;
    [self.glass.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [self.glass.leadingAnchor constraintEqualToAnchor:self.hero.leadingAnchor constant:20],
        [self.glass.trailingAnchor constraintEqualToAnchor:self.hero.trailingAnchor constant:-20],
        [self.glass.topAnchor constraintEqualToAnchor:self.hero.topAnchor constant:8],
        [self.glass.bottomAnchor constraintEqualToAnchor:self.hero.bottomAnchor constant:-8],
        [symbol.widthAnchor constraintEqualToConstant:40],
        [symbol.heightAnchor constraintEqualToConstant:48],
        [stack.topAnchor constraintEqualToAnchor:self.glass.contentView.topAnchor constant:24],
        [stack.bottomAnchor constraintEqualToAnchor:self.glass.contentView.bottomAnchor constant:-24],
        [stack.leadingAnchor constraintEqualToAnchor:self.glass.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:self.glass.contentView.trailingAnchor constant:-20]
    ]];
    self.tableView.tableHeaderView = self.hero;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0 || width == self.heroWidth) return;
    self.heroWidth = width;
    CGFloat height = [self.hero systemLayoutSizeFittingSize:CGSizeMake(width, 0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (height > 0 && isfinite(height)) {
        self.hero.frame = CGRectMake(0, 0, width, ceil(height));
        self.tableView.tableHeaderView = self.hero;
    }
}
- (void)refresh {
    NSString *style = MTValue(@"menu_style");
    self.navigationController.overrideUserInterfaceStyle = [style isEqual:@"dark"] ? UIUserInterfaceStyleDark : [style isEqual:@"light"] ? UIUserInterfaceStyleLight : UIUserInterfaceStyleUnspecified;
    self.navigationController.view.tintColor = MTAccent();
    self.glass.effect = Glass();
    self.glass.backgroundColor = UIAccessibilityIsReduceTransparencyEnabled() ? UIColor.secondarySystemGroupedBackgroundColor : [MTAccent() colorWithAlphaComponent:0.10];
    [self updateSearchResultsForSearchController:self.search];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    NSString *query = searchController.searchBar.text ?: @"";
    NSMutableArray *sections = [NSMutableArray array];
    for (NSDictionary *section in MTSections()) {
        NSArray *rows = [section[@"rows"] filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *row, NSDictionary *bindings) {
            return !query.length || [[NSString stringWithFormat:@"%@ %@ %@", section[@"title"], row[@"title"], row[@"detail"]] localizedStandardContainsString:query];
        }]];
        if (rows.count) [sections addObject:@{@"title": section[@"title"], @"rows": rows}];
    }
    self.sections = sections;
    [self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self.sections[section][@"rows"] count]; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return section < (NSInteger)self.sections.count ? self.sections[section][@"title"] : nil; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == (NSInteger)self.sections.count - 1 ? MTText(@"Параметры сохраняются на устройстве. Серые переключатели означают, что обработчик не найден. iOS 27 ещё не проверена.", @"Preferences stay on device. Disabled switches mean a hook was not found. iOS 27 has not been verified.") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *sections = self.sections;
    UITableViewCell *empty = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (indexPath.section >= (NSInteger)sections.count) return empty;
    NSArray *rows = sections[indexPath.section][@"rows"];
    if (indexPath.row >= (NSInteger)rows.count) return empty;
    NSDictionary *row = rows[indexPath.row];
    NSString *key = row[@"key"], *kind = row[@"kind"];
    BOOL info = [kind isEqual:@"info"], log = [kind isEqual:@"diagnostics"];
    BOOL passive = info || log || [kind isEqual:@"action"];
    BOOL available = MTAvailable(key) || passive;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = row[@"title"];
    NSMutableArray *details = [NSMutableArray array];
    if ([row[@"detail"] length]) [details addObject:row[@"detail"]];
    if ([kind isEqual:@"choice"]) for (NSArray *choice in row[@"choices"]) if ([choice[0] isEqual:MTValue(key)]) [details insertObject:choice[1] atIndex:0];
    if ([kind isEqual:@"country"]) [details insertObject:MTCountry()[@"name"] atIndex:0];
    if ([kind isEqual:@"tags"]) [details insertObject:[MTValue(key) componentsJoinedByString:@", "] atIndex:0];
    if ([kind isEqual:@"date"]) [details insertObject:[MTValue(key) length] ? MTValue(key) : MTText(@"не задано", @"not set") atIndex:0];
    if ([kind isEqual:@"account"]) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"cat.narezany.margyt.ios"];
        NSString *uid = [defaults stringForKey:@"account_uid"], *sec = [defaults stringForKey:@"account_sec_uid"];
        if (!uid.length) {
            id service = MTGet(NSClassFromString(@"AWEUserService"), @"sharedService");
            uid = MTGet(service, @"userID");
            sec = MTGet(MTGet(service, @"currentUserBasicModel"), @"secUserID");
            if ([uid isKindOfClass:NSString.class] && uid.length) [defaults setObject:uid forKey:@"account_uid"];
            if ([sec isKindOfClass:NSString.class] && sec.length) [defaults setObject:sec forKey:@"account_sec_uid"];
        }
        [details insertObject:[NSString stringWithFormat:@"uid: %@\nsec_uid: %@", uid.length ? uid : @"—", sec.length ? sec : @"—"] atIndex:0];
    }
    if (!available) [details addObject:MTText(@"Недоступно: обработчик не найден", @"Unavailable: hook not found")];
    content.secondaryText = [details componentsJoinedByString:@"\n"];
    content.textProperties.numberOfLines = 0;
    content.secondaryTextProperties.numberOfLines = 0;
    content.secondaryTextProperties.color = UIColor.secondaryLabelColor;
    content.image = [UIImage systemImageNamed:row[@"symbol"]];
    content.imageProperties.tintColor = info ? UIColor.secondaryLabelColor : MTAccent();
    content.imageProperties.maximumSize = CGSizeMake(26, 26);
    content.directionalLayoutMargins = NSDirectionalEdgeInsetsMake(14, 16, 14, 16);
    cell.contentConfiguration = content;
    cell.accessibilityIdentifier = [@"margyt." stringByAppendingString:key];
    if ([kind isEqual:@"toggle"]) {
        UISwitch *toggle = [UISwitch new];
        toggle.on = MTBool(key);
        toggle.enabled = available;
        toggle.onTintColor = MTAccent();
        toggle.accessibilityIdentifier = key;
        toggle.accessibilityLabel = row[@"title"];
        [toggle addTarget:self action:@selector(toggled:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = toggle;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)toggled:(UISwitch *)sender {
    MTSet(sender.accessibilityIdentifier, @(sender.on));
    if (!UIAccessibilityIsReduceMotionEnabled()) [[[UISelectionFeedbackGenerator alloc] init] selectionChanged];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSArray *sections = self.sections;
    if (indexPath.section >= (NSInteger)sections.count) return;
    NSArray *rows = sections[indexPath.section][@"rows"];
    if (indexPath.row >= (NSInteger)rows.count) return;
    NSDictionary *row = rows[indexPath.row];
    NSString *kind = row[@"kind"], *key = row[@"key"];
    if ([kind isEqual:@"info"] || (!MTAvailable(key) && ![kind isEqual:@"diagnostics"] && ![kind isEqual:@"action"])) {
        MTShowMessage(self, row[@"title"], row[@"detail"]);
    } else if ([kind isEqual:@"account"]) {
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:@"cat.narezany.margyt.ios"];
        NSString *uid = [defaults stringForKey:@"account_uid"], *sec = [defaults stringForKey:@"account_sec_uid"];
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:row[@"title"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        sheet.popoverPresentationController.sourceView = cell;
        sheet.popoverPresentationController.sourceRect = cell.bounds;
        if (uid.length) [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:MTText(@"Копировать uid: %@", @"Copy uid: %@"), uid] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { UIPasteboard.generalPasteboard.string = uid; }]];
        if (sec.length) [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:MTText(@"Копировать sec_uid: %@", @"Copy sec_uid: %@"), sec] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) { UIPasteboard.generalPasteboard.string = sec; }]];
        if (!uid.length && !sec.length) sheet.message = MTText(@"ID ещё не прочитан — откройте ленту и вернитесь", @"The ID has not been read yet — open the feed and come back");
        [sheet addAction:[UIAlertAction actionWithTitle:MTText(@"Отмена", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:sheet animated:YES completion:nil];
    } else if ([kind isEqual:@"action"] && [key isEqual:@"update_check"]) {
        [self checkUpdate];
    } else if ([kind isEqual:@"diagnostics"]) {
        [self.navigationController pushViewController:[MTLogController new] animated:!UIAccessibilityIsReduceMotionEnabled()];
    } else if ([kind isEqual:@"country"] || [kind isEqual:@"choice"]) {
        MTChoiceController *picker = [[MTChoiceController alloc] initWithStyle:UITableViewStyleInsetGrouped];
        picker.key = key;
        picker.title = row[@"title"];
        picker.choices = row[@"choices"];
        if ([kind isEqual:@"country"]) {
            NSMutableArray *countries = [NSMutableArray array];
            for (NSDictionary *country in MTCountries()) {
                NSString *name = [NSLocale.currentLocale displayNameForKey:NSLocaleCountryCode value:[country[@"iso"] uppercaseString]] ?: country[@"name"];
                NSString *detail = [NSString stringWithFormat:@"%@ · %@%@", country[@"carrier"], country[@"mcc"], country[@"mnc"]];
                [countries addObject:@[country[@"iso"], name, detail]];
            }
            picker.choices = countries;
        }
        [self.navigationController pushViewController:picker animated:!UIAccessibilityIsReduceMotionEnabled()];
    } else if ([kind isEqual:@"tags"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:row[@"title"] message:row[@"detail"] preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = [MTValue(key) componentsJoinedByString:@", "];
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.placeholder = @"cat, travel";
        }];
        [alert addAction:[UIAlertAction actionWithTitle:MTText(@"Отмена", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        __weak UIAlertController *weakAlert = alert;
        [alert addAction:[UIAlertAction actionWithTitle:MTText(@"Сохранить", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *text = weakAlert.textFields.firstObject.text ?: @"";
            BOOL valid = text.length <= 4096 && MTSet(key, [text componentsSeparatedByString:@","]);
            if (!valid) dispatch_async(dispatch_get_main_queue(), ^{ MTShowMessage(self, MTText(@"Проверьте хештеги", @"Check your hashtags"), MTText(@"Не более 40 тегов по 100 символов. Только буквы, цифры и подчёркивание.", @"At most 40 tags of 100 characters. Letters, numbers and underscores only.")); });
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    } else if ([kind isEqual:@"date"]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:row[@"title"] message:row[@"detail"] preferredStyle:UIAlertControllerStyleAlert];
        [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.text = MTValue(key);
            field.autocorrectionType = UITextAutocorrectionTypeNo;
            field.autocapitalizationType = UITextAutocapitalizationTypeNone;
            field.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
            field.placeholder = @"YYYY-MM-DD";
        }];
        [alert addAction:[UIAlertAction actionWithTitle:MTText(@"Отмена", @"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        __weak UIAlertController *weakAlert = alert;
        [alert addAction:[UIAlertAction actionWithTitle:MTText(@"Сохранить", @"Save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *text = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] ?: @"";
            if (!MTSet(key, text)) dispatch_async(dispatch_get_main_queue(), ^{ MTShowMessage(self, row[@"title"], MTText(@"Формат ГГГГ-ММ-ДД, например 2025-01-31. Очистите поле, чтобы отключить.", @"YYYY-MM-DD format, e.g. 2025-01-31. Clear the field to disable.")); });
        }]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

- (void)checkUpdate {
    NSURL *url = [NSURL URLWithString:@"https://raw.githubusercontent.com/1325ilya/TikTokMDIos/main/VERSION"];
    [[NSURLSession.sharedSession dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSString *latest = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        BOOL newer = latest.length && ![latest isEqual:MTVersion] && [latest compare:MTVersion options:NSNumericSearch] == NSOrderedDescending;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error || !latest.length) MTShowMessage(self, @"MargyT", MTText(@"Не удалось проверить обновление", @"Could not check for an update"));
            else if (newer) MTShowMessage(self, @"MargyT", [NSString stringWithFormat:MTText(@"Доступна версия %@ (у вас %@). Соберите и подпишите новый IPA.", @"%@ is available (you have %@). Build and sign the new IPA."), latest, MTVersion]);
            else MTShowMessage(self, @"MargyT", [NSString stringWithFormat:MTText(@"У вас последняя версия (%@)", @"You are on the latest version (%@)"), MTVersion]);
        });
    }] resume];
}

- (void)catTapped:(UITapGestureRecognizer *)tap {
    static NSUInteger taps;
    static CFAbsoluteTime last;
    static NSArray *cats;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    taps = now - last > 1.0 ? 1 : taps + 1;
    last = now;
    UIView *title = tap.view;
    if (!UIAccessibilityIsReduceMotionEnabled()) {
        [UIView animateWithDuration:0.09 animations:^{ title.transform = CGAffineTransformMakeScale(1.04, 0.82); }
                         completion:^(BOOL done) { [UIView animateWithDuration:0.16 animations:^{ title.transform = CGAffineTransformIdentity; }]; }];
    }
    if (taps < 5) {
        if (!cats) [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:@"https://raw.githubusercontent.com/narezany/Margelet/main/cats.json"] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            if (!error && data) cats = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        }] resume];
        return;
    }
    taps = 0;
    if (![cats isKindOfClass:NSArray.class] || !cats.count) { MTShowMessage(self, @"MargyT", MTText(@"Котики ещё в пути…", @"The cats are still on their way…")); return; }
    NSDictionary *cat = cats[arc4random_uniform((uint32_t)cats.count)];
    NSString *photo = cat[@"photo"];
    if (![photo isKindOfClass:NSString.class] || !photo.length) return;
    NSString *language = NSLocale.preferredLanguages.firstObject;
    NSString *name = cat[[@"name_" stringByAppendingString:[language substringToIndex:MIN(2, language.length)]]] ?: cat[@"name"] ?: @"";
    NSString *from = [cat[@"from"] isKindOfClass:NSString.class] ? cat[@"from"] : @"";
    [[NSURLSession.sharedSession dataTaskWithURL:[NSURL URLWithString:[@"https://raw.githubusercontent.com/narezany/Margelet/main/" stringByAppendingString:photo]] completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        UIImage *image = data ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!image) return;
            UIViewController *viewer = [UIViewController new];
            UIImageView *picture = [[UIImageView alloc] initWithImage:image];
            picture.contentMode = UIViewContentModeScaleAspectFit;
            picture.translatesAutoresizingMaskIntoConstraints = NO;
            UILabel *caption = [UILabel new];
            caption.text = from.length ? [NSString stringWithFormat:@"%@ · %@", name, from] : name;
            caption.textAlignment = NSTextAlignmentCenter;
            caption.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
            caption.textColor = UIColor.secondaryLabelColor;
            caption.numberOfLines = 0;
            caption.translatesAutoresizingMaskIntoConstraints = NO;
            viewer.view.backgroundColor = UIColor.systemBackgroundColor;
            [viewer.view addSubview:picture];
            [viewer.view addSubview:caption];
            [NSLayoutConstraint activateConstraints:@[
                [picture.topAnchor constraintEqualToAnchor:viewer.view.safeAreaLayoutGuide.topAnchor],
                [picture.leadingAnchor constraintEqualToAnchor:viewer.view.leadingAnchor],
                [picture.trailingAnchor constraintEqualToAnchor:viewer.view.trailingAnchor],
                [caption.topAnchor constraintEqualToAnchor:picture.bottomAnchor constant:8],
                [caption.leadingAnchor constraintEqualToAnchor:viewer.view.leadingAnchor constant:16],
                [caption.trailingAnchor constraintEqualToAnchor:viewer.view.trailingAnchor constant:-16],
                [caption.bottomAnchor constraintEqualToAnchor:viewer.view.safeAreaLayoutGuide.bottomAnchor constant:-8]
            ]];
            viewer.title = name.length ? name : @"MargyT";
            [self.navigationController pushViewController:viewer animated:!UIAccessibilityIsReduceMotionEnabled()];
        });
    }] resume];
}
@end

void MTPresentSettings(UIViewController *presenter) {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ MTPresentSettings(presenter); });
        return;
    }
    presenter = presenter ?: MTTopController(MTActiveWindow());
    if (!presenter || !presenter.view.window || presenter.isBeingDismissed || presenter.isBeingPresented) return;
    if ([presenter isKindOfClass:MTSettingsController.class] || [presenter.navigationController.viewControllers.firstObject isKindOfClass:MTSettingsController.class]) return;
    if (presenter.presentedViewController) return;
    MTSettingsController *settings = [[MTSettingsController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
    navigation.modalPresentationStyle = UIModalPresentationPageSheet;
    if (@available(iOS 15.0, *)) {
        navigation.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
        navigation.sheetPresentationController.prefersGrabberVisible = YES;
        navigation.sheetPresentationController.preferredCornerRadius = 30;
    }
    [presenter presentViewController:navigation animated:!UIAccessibilityIsReduceMotionEnabled() completion:nil];
}
