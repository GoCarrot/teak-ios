/* Teak -- Copyright (C) 2016 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "Teak+Internal.h"
#import <Teak/Teak.h>
#import <objc/runtime.h>

@interface TeakAppDelegateHooks : NSObject

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

- (BOOL)application:(UIApplication*)application
              openURL:(NSURL*)url
    sourceApplication:(NSString*)sourceApplication
           annotation:(id)annotation;

- (void)applicationDidBecomeActive:(UIApplication*)application;

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings;

- (void)application:(UIApplication*)application didFailToRegisterForRemoteNotificationsWithError:(NSError*)error;

- (void)applicationWillResignActive:(UIApplication*)application;

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;

- (BOOL)application:(UIApplication*)application continueUserActivity:(NSUserActivity*)userActivity restorationHandler:(void (^)(NSArray* _Nullable))restorationHandler;

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler;

@end

static BOOL (*sHostAppDidFinishLaunching)(id, SEL, UIApplication*, NSDictionary*) = NULL;
static BOOL (*sHostAppOpenURLIMP)(id, SEL, UIApplication*, NSURL*, NSString*, id) = NULL;
static void (*sHostWEFIMP)(id, SEL, UIApplication*) = NULL;
static void (*sHostAppPushRegIMP)(id, SEL, UIApplication*, NSData*) = NULL;
static void (*sHostAppPushDidRegIMP)(id, SEL, UIApplication*, UIUserNotificationSettings*) = NULL;
static void (*sHostAppPushRegFailIMP)(id, SEL, UIApplication*, NSError*) = NULL;
static void (*sHostWREIMP)(id, SEL, UIApplication*) = NULL;
static void (*sHostDRRNIMP)(id, SEL, UIApplication*, NSDictionary*) = NULL;
static BOOL (*sHostContinueUserActivityIMP)(id, SEL, UIApplication*, NSUserActivity*, void (^)(NSArray* _Nullable)) = NULL;
static void (*sHostDRRNFCHIMP)(id, SEL, UIApplication*, NSDictionary*, void (^)(UIBackgroundFetchResult)) = NULL;

void __Teak_unregisterForRemoteNotifications(id self, SEL _cmd);
static IMP __App_unregisterForRemoteNotifications = NULL;

extern Teak* _teakSharedInstance;

void Teak_Plant(Class appDelegateClass, NSString* appId, NSString* appSecret) {
  // Allocate and initialize Teak, if it returns nil no hooks will be installed
  _teakSharedInstance = [[Teak alloc] initWithApplicationId:appId andSecret:appSecret];
  if (_teakSharedInstance == nil) {
    TeakLog_e(@"sdk.init", @"initWithApplicationId:andSecret returned nil, Teak is disabled.");
    return;
  }

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
  {
    struct objc_method_description appPushDidRegMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didRegisterUserNotificationSettings:), NO, YES);

    Method ctAppPushDidReg = class_getInstanceMethod([TeakAppDelegateHooks class], appPushDidRegMethod.name);
    sHostAppPushDidRegIMP = (void (*)(id, SEL, UIApplication*, UIUserNotificationSettings*))class_replaceMethod(appDelegateClass, appPushDidRegMethod.name, method_getImplementation(ctAppPushDidReg), appPushDidRegMethod.types);
  }

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

  // application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo fetchCompletionHandler:(void (^)(UIBackgroundFetchResult))handler
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

  if (sHostAppOpenURLIMP) {
    ret |= sHostAppOpenURLIMP(self, @selector(application:openURL:sourceApplication:annotation:), application, url, sourceApplication, annotation);
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

- (void)application:(UIApplication*)application didRegisterUserNotificationSettings:(UIUserNotificationSettings*)notificationSettings {
  [[Teak sharedInstance] application:application didRegisterUserNotificationSettings:notificationSettings];
  if (sHostAppPushDidRegIMP) {
    sHostAppPushDidRegIMP(self, @selector(application:didRegisterUserNotificationSettings:), application, notificationSettings);
  }
}

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

@end

void __Teak_unregisterForRemoteNotifications(id self, SEL _cmd) {
  NSArray* stacktrace = [TeakRaven stacktraceSkippingFrames:2];
  if (stacktrace != nil) {
    if ([Teak sharedInstance] != nil) {
      TeakLog_e(@"application.unregisterForRemoteNotifications", @{@"stacktrace" : stacktrace});
    } else {
      NSLog(@"[Teak] 'unregisterForRemoteNotifications' was called, this should almost never be called. Callstack: %@", stacktrace);
    }
  }

  BOOL blackhole = NO;
  @try {
    blackhole = [[[NSUserDefaults standardUserDefaults] objectForKey:kBlackholeUnregisterForRemoteNotifications] boolValue];
  } @catch (NSException* ignored) {
  }

  if (!blackhole && __App_unregisterForRemoteNotifications != NULL) {
    ((void (*)(id, SEL))__App_unregisterForRemoteNotifications)(self, _cmd);
  }
}
