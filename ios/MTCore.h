#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

FOUNDATION_EXPORT NSString *const MTSettingsChanged;
FOUNDATION_EXPORT NSString *const MTVersion;
FOUNDATION_EXPORT NSString *MTText(NSString *russian, NSString *english);
FOUNDATION_EXPORT NSArray<NSDictionary *> *MTSections(void);
FOUNDATION_EXPORT NSArray<NSDictionary *> *MTCountries(void);
FOUNDATION_EXPORT NSDictionary *MTCountry(void);
FOUNDATION_EXPORT id MTValue(NSString *key);
FOUNDATION_EXPORT BOOL MTBool(NSString *key);
FOUNDATION_EXPORT BOOL MTSet(NSString *key, id value);
FOUNDATION_EXPORT UIColor *MTAccent(void);
FOUNDATION_EXPORT UIColor *MTColor(NSString *hex);
FOUNDATION_EXPORT void MTNote(NSString *message);
FOUNDATION_EXPORT NSString *MTDiagnostics(void);
FOUNDATION_EXPORT NSString *MTSupportPath(NSString *name);
FOUNDATION_EXPORT void MTCapability(NSString *key, BOOL ready);
FOUNDATION_EXPORT BOOL MTAvailable(NSString *key);
FOUNDATION_EXPORT BOOL MTMatches(id object, SEL selector, const char *signature);
FOUNDATION_EXPORT id MTGet(id object, NSString *selector);
FOUNDATION_EXPORT BOOL MTHook(NSString *className, NSString *selector, BOOL classMethod,
                              const char *signature, id (^makeBlock)(IMP original));
FOUNDATION_EXPORT NSArray *MTFilterFeed(NSArray *items);
FOUNDATION_EXPORT BOOL MTBlocksCaption(NSString *caption, NSArray<NSString *> *tags);
FOUNDATION_EXPORT UIViewController *MTTopController(UIWindow *window);
FOUNDATION_EXPORT UIWindow *MTActiveWindow(void);
FOUNDATION_EXPORT void MTPresentSettings(UIViewController *presenter);
FOUNDATION_EXPORT void MTInstallHooks(void);
FOUNDATION_EXPORT void MTInstallAppearance(void);
FOUNDATION_EXPORT void MTShowMessage(UIViewController *presenter, NSString *title, NSString *message);
