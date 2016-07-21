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

#include <Foundation/Foundation.h>

/**
 * Use this named notification to listen for when your app gets launched from a Teak notification.
 * [[NSNotificationCenter defaultCenter] addObserver:self
 *                                          selector:@selector(handleTeakNotification)
 *                                               name:TeakNotificationAppLaunch
 *                                             object:nil];
 */
extern NSString* _Nonnull const TeakNotificationAppLaunch;

#ifdef __OBJC__

#import <UIKit/UIKit.h>
#import <Teak/TeakNotification.h>

@interface Teak : NSObject

/**
 * Is debug logging enabled.
 *
 * Disabled by default in production, enabled otherwise.
 */
@property (nonatomic, readonly) BOOL enableDebugOutput;

/**
 * Teak SDK Version.
 */
@property (strong, nonatomic, readonly) NSString* _Nonnull sdkVersion;

/**
 * Set up Teak in a single function call.
 *
 * This function *must* be called from no other place than main() in your application's
 * 'main.m' or 'main.mm' file before UIApplicationMain() is called. Ex:
 *
 * 	int main(int argc, char *argv[])
 * 	{
 * 		@autoreleasepool {
 * 			// Add this line here.
 * 			[Teak initForApplicationId:@"your_app_id" withClass:[YourAppDelegate class] andApiKey:@"your_api_key"];
 *
 * 			return UIApplicationMain(argc, argv, nil, NSStringFromClass([YourAppDelegate class]));
 * 		}
 * 	}
 *
 * @param appId            Teak Application Id
 * @param appDelegateClass Class of your application delegate, ex: [YourAppDelegate class].
 * @param apiKey           Your Teak API key.
 */
+ (void)initForApplicationId:(nonnull NSString*)appId withClass:(nonnull Class)appDelegateClass andApiKey:(nonnull NSString*)apiKey;

/**
 * Teak singleton.
 */
+ (nullable Teak*)sharedInstance;

/**
 * Tell Teak how to identify the current user.
 *
 * This should be how you identify the user in your back-end.
 *
 * @param userId           The string Teak should use to identify the current user.
 */
- (void)identifyUser:(nonnull NSString*)userId;

/**
 * Track an arbitrary event in Teak.
 *
 * @param actionId         The identifier for the action, e.g. 'complete'.
 * @param objectTypeId     The type of object that is being posted, e.g. 'quest'.
 * @param objectInstanceId The specific instance of the object, e.g. 'gather-quest-1'
 */
- (void)trackEventWithActionId:(nonnull NSString*)actionId forObjectTypeId:(nullable NSString*)objectTypeId andObjectInstanceId:(nullable NSString*)objectInstanceId;

@end

#endif /* __OBJC__ */
