#import "Teak+Internal.h"
#import <Teak/Teak.h>
#import <objc/runtime.h>

@interface TeakAppDelegateHooks : NSObject

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

- (BOOL)application:(UIApplication*)application
              openURL:(NSURL*)url
    sourceApplication:(NSString*)sourceApplication
           annotation:(id)annotation;

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url options:(NSDictionary<NSString*, id>*)options;

- (void)applicationDidBecomeActive:(UIApplication*)application;

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;
#pragma clang diagnostic pop

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;

- (void)applicationWillResignActive:(UIApplication*)application;

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;

- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler;

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler;

@end

BOOL(*sHostAppDidFinishLaunching)
(id, SEL, UIApplication*, NSDictionary*) = NULL;
BOOL(*sHostAppOpenURLIMP)
(id, SEL, UIApplication*, NSURL*, NSString*, id) = NULL;
BOOL(*sHostAppOpenURLOptionsIMP)
(id, SEL, UIApplication*, NSURL*, NSDictionary<NSString*, id>*) = NULL;
void (*sHostWEFIMP)(id, SEL, UIApplication*) = NULL;
void (*sHostAppPushRegIMP)(id, SEL, UIApplication*, NSData*) = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
void (*sHostAppPushDidRegIMP)(id, SEL, UIApplication*, UIUserNotificationSettings*) = NULL;
#pragma clang diagnostic pop
void (*sHostAppPushRegFailIMP)(id, SEL, UIApplication*, NSError*) = NULL;
void (*sHostWREIMP)(id, SEL, UIApplication*) = NULL;
void (*sHostDRRNIMP)(id, SEL, UIApplication*, NSDictionary*) = NULL;
BOOL(*sHostContinueUserActivityIMP)
(id, SEL, UIApplication*, NSUserActivity*, void (^)(NSArray* _Nullable)) = NULL;
void (*sHostDRRNFCHIMP)(id, SEL, UIApplication*, NSDictionary*, void (^)(UIBackgroundFetchResult)) = NULL;
void (*sHostUNCWPNWCH)(id, SEL, UNUserNotificationCenter*, UNNotification*, void(^)(UNNotificationPresentationOptions)) = NULL;
void (*sHostUNCDRNRWCH)(id, SEL, UNUserNotificationCenter*, UNNotificationResponse*, void(^)(void)) = NULL;

void __Teak_unregisterForRemoteNotifications(id self, SEL _cmd);
IMP __App_unregisterForRemoteNotifications = NULL;

NSSet* TeakGetNotificationCategorySet(void);
void __Teak_setNotificationCategories(id self, SEL _cmd, NSSet* categories);
IMP __App_setNotificationCategories = NULL;

extern Teak* _teakSharedInstance;

@interface TeakUNUserNotificationCenterDelegateProxy : NSObject

@property(strong, nonatomic) id currentUserNotificationCenterDelegate;

@end

@implementation TeakUNUserNotificationCenterDelegateProxy

+(TeakUNUserNotificationCenterDelegateProxy*)sharedInstance {
  static TeakUNUserNotificationCenterDelegateProxy* proxy;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    proxy = [[TeakUNUserNotificationCenterDelegateProxy alloc] init];
  });
  return proxy;
}

-(TeakUNUserNotificationCenterDelegateProxy*)init {
  self = [super init];
  if(self) {
    @try {
      [[UNUserNotificationCenter currentNotificationCenter] addObserver:self
                              forKeyPath:NSStringFromSelector(@selector(delegate))
                              options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld
                              context:nil];
    } @catch (NSException* exception) {
      TeakLog_e(@"unusernotificationcenter.delegate", @"Error occurred while regiserting KVO observer.", @{@"error" : exception.reason});
    }
  }

  return self;
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
  if ([keyPath isEqualToString:NSStringFromSelector(@selector(delegate))]) {
    id oldDelegate = change[NSKeyValueChangeOldKey];
    if (oldDelegate && oldDelegate != [NSNull null]) {
      [self unswizzleUserNotificationCenterDelegate:oldDelegate];
    }
    id newDelegate = change[NSKeyValueChangeNewKey];
    if (newDelegate && newDelegate != [NSNull null]) {
      [self swizzleUserNotificationCenterDelegate:newDelegate];
    }
  }
}

-(void)unswizzleUserNotificationCenterDelegate:(id)delegate {
  // Stop if this isn't our currently swizzled delegate.
  if(self.currentUserNotificationCenterDelegate != delegate) {
    return;
  }

  // Stop if this is the delegate that we set.
  if(delegate == _teakSharedInstance) {
    return;
  }

  if(delegate == nil) {
    return;
  }

  Protocol* unUserNotificationCenterDelegateProto = objc_getProtocol("UNUserNotificationCenterDelegate");
  if(sHostUNCWPNWCH) {
    struct objc_method_description uncwpnwch = protocol_getMethodDescription(unUserNotificationCenterDelegateProto, @selector(userNotificationCenter:willPresentNotification:withCompletionHandler:), NO, YES);

    class_replaceMethod([delegate class], uncwpnwch.name, (IMP)sHostUNCWPNWCH, uncwpnwch.types);
    sHostUNCWPNWCH = NULL;
  }

  if(sHostUNCDRNRWCH) {
    struct objc_method_description uncdrnrwch = protocol_getMethodDescription(unUserNotificationCenterDelegateProto, @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:), NO, YES);

    class_replaceMethod([delegate class], uncdrnrwch.name, (IMP)sHostUNCDRNRWCH, uncdrnrwch.types);
    sHostUNCDRNRWCH = NULL;
  }

  self.currentUserNotificationCenterDelegate = nil;
}

-(void)swizzleUserNotificationCenterDelegate:(id)delegate {
  // Stop if we already swizzeled this delegate
  if(self.currentUserNotificationCenterDelegate == delegate) {
    return;
  }

  // Stop if this is the delegate that we set.
  if(delegate == _teakSharedInstance) {
    return;
  }

  if(delegate == nil) {
    return;
  }

  Protocol* unUserNotificationCenterDelegateProto = objc_getProtocol("UNUserNotificationCenterDelegate");
  {
    struct objc_method_description uncwpnwch = protocol_getMethodDescription(unUserNotificationCenterDelegateProto, @selector(userNotificationCenter:willPresentNotification:withCompletionHandler:), NO, YES);

    Method ctUNCWPNWCH = class_getInstanceMethod([TeakAppDelegateHooks class], uncwpnwch.name);
    sHostUNCWPNWCH = (void(*)(id, SEL, UNUserNotificationCenter*, UNNotification*, void(^)(UNNotificationPresentationOptions)))class_replaceMethod([delegate class], uncwpnwch.name, method_getImplementation(ctUNCWPNWCH), uncwpnwch.types);
  }

  {
    struct objc_method_description uncdrnrwch = protocol_getMethodDescription(unUserNotificationCenterDelegateProto, @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:), NO, YES);

    Method ctUNCDRNRWCH = class_getInstanceMethod([TeakAppDelegateHooks class], uncdrnrwch.name);
    sHostUNCDRNRWCH = (void(*)(id, SEL, UNUserNotificationCenter*, UNNotificationResponse*, void(^)(void)))class_replaceMethod([delegate class], uncdrnrwch.name, method_getImplementation(ctUNCDRNRWCH), uncdrnrwch.types);
  }

  self.currentUserNotificationCenterDelegate = delegate;
}

@end

void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret) {
  // Allocate and initialize Teak, if it returns nil no hooks will be installed
  _teakSharedInstance = [[Teak alloc] initWithApplicationId:appId andSecret:appSecret];
  if (_teakSharedInstance == nil) {
    TeakLog_e(@"sdk.init", @"initWithApplicationId:andSecret returned nil, Teak is disabled.");
    return;
  }

  [TeakUNUserNotificationCenterDelegateProxy sharedInstance];

  // Install hooks
  Protocol* uiAppDelegateProto = objc_getProtocol("UIApplicationDelegate");

  // application:didFinishLaunchingWithOptions:
  {
    struct objc_method_description appDidFinishLaunchingMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didFinishLaunchingWithOptions:), NO, YES);

    Method ctDidFinishLaunching = class_getInstanceMethod([TeakAppDelegateHooks class], appDidFinishLaunchingMethod.name);
    sHostAppDidFinishLaunching = (BOOL(*)(id, SEL, UIApplication*, NSDictionary*))class_replaceMethod(appDelegateClass, appDidFinishLaunchingMethod.name, method_getImplementation(ctDidFinishLaunching), appDidFinishLaunchingMethod.types);
  }

  // application:openURL:sourceApplication:annotation:
  {
    struct objc_method_description appOpenURLMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:openURL:sourceApplication:annotation:), NO, YES);

    Method ctAppOpenURL = class_getInstanceMethod([TeakAppDelegateHooks class], appOpenURLMethod.name);
    sHostAppOpenURLIMP = (BOOL(*)(id, SEL, UIApplication*, NSURL*, NSString*, id))class_replaceMethod(appDelegateClass, appOpenURLMethod.name, method_getImplementation(ctAppOpenURL), appOpenURLMethod.types);
  }

  // application:openURL:options:
  if (class_respondsToSelector(appDelegateClass, @selector(application:openURL:options:))) {
    TeakLog_i(@"sdk.init", @"Found application:openURL:options:");
    struct objc_method_description desc = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:openURL:options:), NO, YES);
    Method m = class_getInstanceMethod([TeakAppDelegateHooks class], desc.name);
    sHostAppOpenURLOptionsIMP = (BOOL(*)(id, SEL, UIApplication*, NSURL*, NSDictionary<NSString*, id>*))class_replaceMethod(appDelegateClass, desc.name, method_getImplementation(m), desc.types);
  }

  // applicationDidBecomeActive:
  {
    struct objc_method_description appWEFMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(applicationDidBecomeActive:), NO, YES);

    Method ctAppDBA = class_getInstanceMethod([TeakAppDelegateHooks class], appWEFMethod.name);
    sHostWEFIMP = (void (*)(id, SEL, UIApplication*))class_replaceMethod(appDelegateClass, appWEFMethod.name, method_getImplementation(ctAppDBA), appWEFMethod.types);
  }

  // application:didRegisterForRemoteNotificationsWithDeviceToken:
  {
    struct objc_method_description appPushRegMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), NO, YES);

    Method ctAppPushReg = class_getInstanceMethod([TeakAppDelegateHooks class], appPushRegMethod.name);
    sHostAppPushRegIMP = (void (*)(id, SEL, UIApplication*, NSData*))class_replaceMethod(appDelegateClass, appPushRegMethod.name, method_getImplementation(ctAppPushReg), appPushRegMethod.types);
  }

  // application:didRegisterUserNotificationSettings:
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
  {
    struct objc_method_description appPushDidRegMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didRegisterUserNotificationSettings:), NO, YES);

    Method ctAppPushDidReg = class_getInstanceMethod([TeakAppDelegateHooks class], appPushDidRegMethod.name);
    sHostAppPushDidRegIMP = (void (*)(id, SEL, UIApplication*, UIUserNotificationSettings*))class_replaceMethod(appDelegateClass, appPushDidRegMethod.name, method_getImplementation(ctAppPushDidReg), appPushDidRegMethod.types);
  }
#pragma clang diagnostic pop

  // application:didFailToRegisterForRemoteNotificationsWithError:
  {
    struct objc_method_description appPushRegFailMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didFailToRegisterForRemoteNotificationsWithError:), NO, YES);

    Method ctAppPushRegFail = class_getInstanceMethod([TeakAppDelegateHooks class], appPushRegFailMethod.name);
    sHostAppPushRegFailIMP = (void (*)(id, SEL, UIApplication*, NSError*))class_replaceMethod(appDelegateClass, appPushRegFailMethod.name, method_getImplementation(ctAppPushRegFail), appPushRegFailMethod.types);
  }

  // applicationWillResignActive:
  {
    struct objc_method_description appWREMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(applicationWillResignActive:), NO, YES);

    Method ctAppWRE = class_getInstanceMethod([TeakAppDelegateHooks class], appWREMethod.name);
    sHostWREIMP = (void (*)(id, SEL, UIApplication*))class_replaceMethod(appDelegateClass, appWREMethod.name, method_getImplementation(ctAppWRE), appWREMethod.types);
  }

  // application:didReceiveRemoteNotification:
  {
    struct objc_method_description appDRRNMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didReceiveRemoteNotification:), NO, YES);

    Method ctAppDRRN = class_getInstanceMethod([TeakAppDelegateHooks class], appDRRNMethod.name);
    sHostDRRNIMP = (void (*)(id, SEL, UIApplication*, NSDictionary*))class_replaceMethod(appDelegateClass, appDRRNMethod.name, method_getImplementation(ctAppDRRN), appDRRNMethod.types);
  }

  // application:continueUserActivity:restorationHandler:
  {
    struct objc_method_description appContinueUserActivityMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:continueUserActivity:restorationHandler:), NO, YES);

    Method ctAppContinueUserActivity = class_getInstanceMethod([TeakAppDelegateHooks class], appContinueUserActivityMethod.name);
    sHostContinueUserActivityIMP = (BOOL(*)(id, SEL, UIApplication*, NSUserActivity*, void (^)(NSArray* _Nullable)))class_replaceMethod(appDelegateClass, appContinueUserActivityMethod.name, method_getImplementation(ctAppContinueUserActivity), appContinueUserActivityMethod.types);
  }

  // application:didReceiveRemoteNotification:fetchCompletionHandler:
  {
    struct objc_method_description appDRRNFCHMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:), NO, YES);

    Method ctAppDRRNFCH = class_getInstanceMethod([TeakAppDelegateHooks class], appDRRNFCHMethod.name);
    sHostDRRNFCHIMP = (void (*)(id, SEL, UIApplication*, NSDictionary*, void (^)(UIBackgroundFetchResult)))class_replaceMethod(appDelegateClass, appDRRNFCHMethod.name, method_getImplementation(ctAppDRRNFCH), appDRRNFCHMethod.types);
  }

  /////
  // UIApplication
  Class uiApplicationClass = objc_getClass("UIApplication");

  // unregisterForRemoteNotifications
  {
    Method m = class_getInstanceMethod(uiApplicationClass, @selector(unregisterForRemoteNotifications));
    __App_unregisterForRemoteNotifications = method_setImplementation(m, (IMP)__Teak_unregisterForRemoteNotifications);
  }

  /////
  // UNNotificationCenter
  Class unUserNotificationCenterClass = objc_getClass("UNUserNotificationCenter");
  if (unUserNotificationCenterClass != nil) {
    // setNotificationCategories
    {
      Method m = class_getInstanceMethod(unUserNotificationCenterClass, @selector(setNotificationCategories:));
      __App_setNotificationCategories = method_setImplementation(m, (IMP)__Teak_setNotificationCategories);
    }
  }
}

@implementation TeakAppDelegateHooks

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  BOOL ret = [[Teak sharedInstance] application:application didFinishLaunchingWithOptions:launchOptions];
  if (sHostAppDidFinishLaunching) {
    ret |= sHostAppDidFinishLaunching(self, @selector(application:didFinishLaunchingWithOptions:), application, launchOptions);
  }
  return ret;
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation {
  BOOL ret = [[Teak sharedInstance] application:application openURL:url sourceApplication:sourceApplication annotation:annotation];

  if (!ret && sHostAppOpenURLIMP) {
    ret |= sHostAppOpenURLIMP(self, @selector(application:openURL:sourceApplication:annotation:), application, url, sourceApplication, annotation);
  }

  return ret;
}

- (BOOL)application:(UIApplication*)application openURL:(NSURL*)url options:(NSDictionary<NSString*, id>*)options {
  BOOL ret = [[Teak sharedInstance] application:application openURL:url options:options];
  if (!ret && sHostAppOpenURLOptionsIMP) {
    ret |= sHostAppOpenURLOptionsIMP(self, @selector(application:openURL:options:), application, url, options);
  }
  return ret;
}

- (void)applicationDidBecomeActive:(UIApplication*)application {
  [[Teak sharedInstance] applicationDidBecomeActive:application];
  if (sHostWEFIMP) {
    sHostWEFIMP(self, @selector(applicationDidBecomeActive:), application);
  }
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken {
  [[Teak sharedInstance] application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
  if (sHostAppPushRegIMP) {
    sHostAppPushRegIMP(self, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), application, deviceToken);
  }
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  [[Teak sharedInstance] application:application didRegisterUserNotificationSettings:notificationSettings];
  if (sHostAppPushDidRegIMP) {
    sHostAppPushDidRegIMP(self, @selector(application:didRegisterUserNotificationSettings:), application, notificationSettings);
  }
}
#pragma clang diagnostic pop

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error {
  [[Teak sharedInstance] application:application didFailToRegisterForRemoteNotificationsWithError:error];
  if (sHostAppPushRegFailIMP) {
    sHostAppPushRegFailIMP(self, @selector(application:didFailToRegisterForRemoteNotificationsWithError:), application, error);
  }
}

- (void)applicationWillResignActive:(UIApplication*)application {
  if (sHostWREIMP) {
    sHostWREIMP(self, @selector(applicationWillResignActive:), application);
  }
  [[Teak sharedInstance] applicationWillResignActive:application];
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler {
  [[Teak sharedInstance] application:application didReceiveRemoteNotification:userInfo];
  if (sHostDRRNFCHIMP) {
    sHostDRRNFCHIMP(self, @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:), application, userInfo, handler);
  } else if (handler != nil) {
    handler(UIBackgroundFetchResultNoData);
  }
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo {
  [[Teak sharedInstance] application:application didReceiveRemoteNotification:userInfo];
  if (sHostDRRNIMP) {
    sHostDRRNIMP(self, @selector(application:didReceiveRemoteNotification:), application, userInfo);
  }
}

- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler {
  BOOL ret = [[Teak sharedInstance] application:application continueUserActivity:userActivity restorationHandler:restorationHandler];

  if (sHostContinueUserActivityIMP) {
    ret |= sHostContinueUserActivityIMP(self, @selector(application:continueUserActivity:restorationHandler:), application, userActivity, restorationHandler);
  }

  return ret;
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center didReceiveNotificationResponse:(UNNotificationResponse*)response withCompletionHandler:(void (^)(void))completionHandler {
  BOOL teakHandled = [Teak didReceiveNotificationResponse:response withCompletionHandler:completionHandler];
  if(sHostUNCDRNRWCH) {
    sHostUNCDRNRWCH(self, @selector(userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:), center, response, completionHandler);
  } else if(!teakHandled) {
    // If the host does not provide an implementation, call the completion handler ourselves for the non-teak notification.
    completionHandler();
  }
}

- (void)userNotificationCenter:(UNUserNotificationCenter*)center willPresentNotification:(UNNotification*)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler {
  BOOL teakHandled = [Teak willPresentNotification:notification withCompletionHandler:completionHandler];
  if(sHostUNCWPNWCH) {
    sHostUNCWPNWCH(self, @selector(userNotificationCenter:willPresentNotification:withCompletionHandler:), center, notification, completionHandler);
  } else if(!teakHandled) {
    // If the host does not provide an implementation, call the completion handler ourselves for the non-teak notification.
    completionHandler(UNNotificationPresentationOptionNone);
  }
}
@end

void __Teak_unregisterForRemoteNotifications(id self, SEL _cmd) {
  NSArray* stacktrace = [TeakRaven stacktraceSkippingFrames:2];
  if (stacktrace != nil) {
    if ([Teak sharedInstance] != nil) {
      TeakLog_e(@"application.unregisterForRemoteNotifications", @{@"stacktrace" : stacktrace});
    } else {
      NSLog(@"Teak: 'unregisterForRemoteNotifications' was called, this should almost never be called. Callstack: %@", stacktrace);
    }
  }

  BOOL blackhole = NO;
  @try {
    blackhole = [[[NSBundle mainBundle] objectForInfoDictionaryKey:kBlackholeUnregisterForRemoteNotifications] boolValue];
  } @catch (NSException* ignored) {
    blackhole = NO;
  }

  if (!blackhole && __App_unregisterForRemoteNotifications != NULL) {
    ((void (*)(id, SEL))__App_unregisterForRemoteNotifications)(self, _cmd);
  }
}

void __Teak_setNotificationCategories(id self, SEL _cmd, NSSet* categories) {
  if (__App_setNotificationCategories != NULL) {
    NSMutableSet* categoriesWithTeakAdded = [NSMutableSet setWithSet:TeakGetNotificationCategorySet()];
    [categoriesWithTeakAdded unionSet:categories];
    ((void (*)(id, SEL, NSSet*))__App_setNotificationCategories)(self, _cmd, categoriesWithTeakAdded);
  }
}

NSSet* TeakGetNotificationCategorySet(void) {
  static NSSet* nonmutableCategories;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    NSMutableSet* categories = [[NSMutableSet alloc] init];
    if (NSClassFromString(@"UNUserNotificationCenter") != nil) {
      for (NSString* key in TeakNotificationCategories) {
        NSDictionary* category = TeakNotificationCategories[key];

        NSMutableArray* actions = [[NSMutableArray alloc] init];
        for (NSArray* actionPair in category[@"actions"]) {
          UNNotificationAction* action = [UNNotificationAction actionWithIdentifier:actionPair[0]
                                                                              title:actionPair[1]
                                                                            options:UNNotificationActionOptionForeground];
          [actions addObject:action];
        }

        UNNotificationCategory* notifCategory = [UNNotificationCategory categoryWithIdentifier:key
                                                                                       actions:actions
                                                                             intentIdentifiers:@[]
                                                                                       options:UNNotificationCategoryOptionCustomDismissAction];
        UNNotificationCategory* buttonOnlyNotifCategory = [UNNotificationCategory categoryWithIdentifier:[NSString stringWithFormat:@"%@_ButtonOnly", key]
                                                                                                 actions:actions
                                                                                       intentIdentifiers:@[]
                                                                                                 options:UNNotificationCategoryOptionCustomDismissAction];
        [categories addObject:notifCategory];
        [categories addObject:buttonOnlyNotifCategory];
      }
      nonmutableCategories = [NSSet setWithSet:categories];
    } else {
      NSLog(@"Teak: Class 'UNUserNotificationCenter' not found. Expanded view notifications are disabled.");
    }
  });
  return nonmutableCategories;
}
