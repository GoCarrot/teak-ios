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

#import <Teak/Teak.h>
#import <objc/runtime.h>
#import "Teak+Internal.h"

@interface TeakAppDelegateHooks : NSObject

- (BOOL)application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions;

- (BOOL)application:(UIApplication*)application
            openURL:(NSURL*)url
  sourceApplication:(NSString*)sourceApplication
         annotation:(id)annotation;

- (void)applicationDidBecomeActive:(UIApplication*)application;

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken;

- (void)applicationWillResignActive:(UIApplication*)application;

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo;
@end

static BOOL (*sHostAppWillFinishLaunching)(id, SEL, UIApplication*, NSDictionary*) = NULL;
static BOOL (*sHostAppDidFinishLaunching)(id, SEL, UIApplication*, NSDictionary*) = NULL;
static BOOL (*sHostAppOpenURLIMP)(id, SEL, UIApplication*, NSURL*, NSString*, id) = NULL;
static void (*sHostDBAIMP)(id, SEL, UIApplication*) = NULL;
static void (*sHostAppPushRegIMP)(id, SEL, UIApplication*, NSData*) = NULL;
static void (*sHostWREIMP)(id, SEL, UIApplication*) = NULL;
static void (*sHostDRRNIMP)(id, SEL, UIApplication*, NSDictionary*) = NULL;

void Teak_Plant(Class appDelegateClass, NSString* appSecret)
{
   // Install hooks
   Protocol* uiAppDelegateProto = objc_getProtocol("UIApplicationDelegate");

   // application:willFinishLaunchingWithOptions:
   struct objc_method_description appWillFinishLaunchingMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:willFinishLaunchingWithOptions:), NO, YES);

   Method ctWillFinishLaunching = class_getInstanceMethod([TeakAppDelegateHooks class], appWillFinishLaunchingMethod.name);
   sHostAppWillFinishLaunching = (BOOL (*)(id, SEL, UIApplication*, NSDictionary*))class_replaceMethod(appDelegateClass, appWillFinishLaunchingMethod.name, method_getImplementation(ctWillFinishLaunching), appWillFinishLaunchingMethod.types);

   // application:didFinishLaunchingWithOptions:
   struct objc_method_description appDidFinishLaunchingMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didFinishLaunchingWithOptions:), NO, YES);
   
   Method ctDidFinishLaunching = class_getInstanceMethod([TeakAppDelegateHooks class], appDidFinishLaunchingMethod.name);
   sHostAppDidFinishLaunching = (BOOL (*)(id, SEL, UIApplication*, NSDictionary*))class_replaceMethod(appDelegateClass, appDidFinishLaunchingMethod.name, method_getImplementation(ctDidFinishLaunching), appDidFinishLaunchingMethod.types);

   // application:openURL:sourceApplication:annotation:
   struct objc_method_description appOpenURLMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:openURL:sourceApplication:annotation:), NO, YES);

   Method ctAppOpenURL = class_getInstanceMethod([TeakAppDelegateHooks class], appOpenURLMethod.name);
   sHostAppOpenURLIMP = (BOOL (*)(id, SEL, UIApplication*, NSURL*, NSString*, id))class_replaceMethod(appDelegateClass, appOpenURLMethod.name, method_getImplementation(ctAppOpenURL), appOpenURLMethod.types);

   // applicationDidBecomeActive:
   struct objc_method_description appDBAMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(applicationDidBecomeActive:), NO, YES);

   Method ctAppDBA = class_getInstanceMethod([TeakAppDelegateHooks class], appDBAMethod.name);
   sHostDBAIMP = (void (*)(id, SEL, UIApplication*))class_replaceMethod(appDelegateClass, appDBAMethod.name, method_getImplementation(ctAppDBA), appDBAMethod.types);

   // application:didRegisterForRemoteNotificationsWithDeviceToken:
   struct objc_method_description appPushRegMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), NO, YES);

   Method ctAppPushReg = class_getInstanceMethod([TeakAppDelegateHooks class], appPushRegMethod.name);
   sHostAppPushRegIMP = (void (*)(id, SEL, UIApplication*, NSData*))class_replaceMethod(appDelegateClass, appPushRegMethod.name, method_getImplementation(ctAppPushReg), appPushRegMethod.types);

   // applicationWillResignActive:
   struct objc_method_description appWREMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(applicationWillResignActive:), NO, YES);

   Method ctAppWRE = class_getInstanceMethod([TeakAppDelegateHooks class], appWREMethod.name);
   sHostWREIMP = (void (*)(id, SEL, UIApplication*))class_replaceMethod(appDelegateClass, appWREMethod.name, method_getImplementation(ctAppWRE), appWREMethod.types);

   // application:didReceiveRemoteNotification:
   struct objc_method_description appDRRNMethod = protocol_getMethodDescription(uiAppDelegateProto, @selector(application:didReceiveRemoteNotification:), NO, YES);

   Method ctAppDRRN = class_getInstanceMethod([TeakAppDelegateHooks class], appDRRNMethod.name);
   sHostDRRNIMP = (void (*)(id, SEL, UIApplication*, NSDictionary*))class_replaceMethod(appDelegateClass, appDRRNMethod.name, method_getImplementation(ctAppDRRN), appDRRNMethod.types);
}

@implementation TeakAppDelegateHooks

- (BOOL)application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
   BOOL ret = [[Teak sharedInstance] application:application willFinishLaunchingWithOptions:launchOptions];
   if(sHostAppWillFinishLaunching)
   {
      ret |= sHostAppWillFinishLaunching(self, @selector(application:willFinishLaunchingWithOptions:), application, launchOptions);
   }
   return ret;
}

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
   BOOL ret = [[Teak sharedInstance] application:application didFinishLaunchingWithOptions:launchOptions];
   if(sHostAppDidFinishLaunching)
   {
      ret |= sHostAppDidFinishLaunching(self, @selector(application:didFinishLaunchingWithOptions:), application, launchOptions);
   }
   return ret;
}

- (BOOL)application:(UIApplication*)application
            openURL:(NSURL*)url
  sourceApplication:(NSString*)sourceApplication
         annotation:(id)annotation
{
   BOOL ret = [[Teak sharedInstance] handleOpenURL:url];
   if(sHostAppOpenURLIMP)
   {
      ret |= sHostAppOpenURLIMP(self, @selector(application:openURL:sourceApplication:annotation:), application, url, sourceApplication, annotation);
   }
   return ret;
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
   [[Teak sharedInstance] applicationDidBecomeActive:application];
   if(sHostDBAIMP)
   {
      sHostDBAIMP(self, @selector(applicationDidBecomeActive:), application);
   }
}

- (void)application:(UIApplication*)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)deviceToken
{
   [[Teak sharedInstance] application:application didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
   if(sHostAppPushRegIMP)
   {
      sHostAppPushRegIMP(self, @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:), application, deviceToken);
   }
}

- (void)applicationWillResignActive:(UIApplication*)application
{
   [[Teak sharedInstance] applicationWillResignActive:application];
   if(sHostWREIMP)
   {
      sHostWREIMP(self, @selector(applicationWillResignActive:), application);
   }
}

- (void)application:(UIApplication*)application didReceiveRemoteNotification:(NSDictionary*)userInfo
{
   [[Teak sharedInstance] application:application didReceiveRemoteNotification:userInfo];
   if(sHostDRRNIMP)
   {
      sHostDRRNIMP(self, @selector(application:didReceiveRemoteNotification:), application, userInfo);
   }
}

@end
