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
    NSArray *choice = self.visible[indexPath.row];
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
    UILabel *detail = [UILabel new];
    detail.text = MTText(@"Нативный интерфейс iOS\nЭкспериментальный перенос · TikTok 46.9.0", @"Native iOS interface\nExperimental port · TikTok 46.9.0");
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
    CGFloat height = [self.hero systemLayoutSizeFittingSize:CGSizeMake(width, 0) withHorizontalFittingPriority:UILayoutPriorityRequired verticalFittingPriority:UILayoutPriorityFittingSizeLevel].height;
    if (height > 0 && (fabs(height - self.hero.bounds.size.height) > 1 || fabs(width - self.hero.bounds.size.width) > 1)) {
        self.hero.frame = CGRectMake(0, 0, width, height);
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
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return self.sections[section][@"title"]; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return section == (NSInteger)self.sections.count - 1 ? MTText(@"Параметры сохраняются на устройстве. Серые переключатели означают, что обработчик не найден. iOS 27 ещё не проверена.", @"Preferences stay on device. Disabled switches mean a hook was not found. iOS 27 has not been verified.") : nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *key = row[@"key"], *kind = row[@"kind"];
    BOOL info = [kind isEqual:@"info"], log = [kind isEqual:@"diagnostics"];
    BOOL available = MTAvailable(key) || info || log;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    content.text = row[@"title"];
    NSMutableArray *details = [NSMutableArray array];
    if ([row[@"detail"] length]) [details addObject:row[@"detail"]];
    if ([kind isEqual:@"choice"]) for (NSArray *choice in row[@"choices"]) if ([choice[0] isEqual:MTValue(key)]) [details insertObject:choice[1] atIndex:0];
    if ([kind isEqual:@"country"]) [details insertObject:MTCountry()[@"name"] atIndex:0];
    if ([kind isEqual:@"tags"]) [details insertObject:[MTValue(key) componentsJoinedByString:@", "] atIndex:0];
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
    NSDictionary *row = self.sections[indexPath.section][@"rows"][indexPath.row];
    NSString *kind = row[@"kind"], *key = row[@"key"];
    if ([kind isEqual:@"info"] || (!MTAvailable(key) && ![kind isEqual:@"diagnostics"])) {
        MTShowMessage(self, row[@"title"], row[@"detail"]);
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
    }
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
