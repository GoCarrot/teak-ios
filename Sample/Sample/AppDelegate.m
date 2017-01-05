//
//  AppDelegate.m
//  Sample
//
//  Created by Pat Wilson on 2/24/16.
//  Copyright © 2016 GoCarrot Inc. All rights reserved.
//

#import "AppDelegate.h"
#import <Teak/Teak.h>

@import AdSupport;

@interface AppDelegate ()

@end

@implementation AppDelegate

- (void)application:(UIApplication*)application handleEventsForBackgroundURLSession:(NSString*)identifier completionHandler:(void (^)())completionHandler
{
   NSLog(@"application:handleEventsForBackgroundURLSession:completionHandler: - Session Identifier: %@", identifier);
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
   NSString* userId = [[ASIdentifierManager sharedManager].advertisingIdentifier UUIDString];
   [[Teak sharedInstance] identifyUser:userId];

   if ([application respondsToSelector:@selector(registerUserNotificationSettings:)]) {
      UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:(UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound) categories:nil];
      [application registerUserNotificationSettings:settings];
   } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      UIRemoteNotificationType myTypes = UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeSound;
      [application registerForRemoteNotificationTypes:myTypes];
#pragma clang diagnostic pop
   }

   [[NSNotificationCenter defaultCenter] addObserver:self
                                            selector:@selector(handleTeakNotification:)
                                                name:TeakNotificationAppLaunch
                                              object:nil];
/*
   NSArray* locales = [NSLocale preferredLanguages];
   NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
   NSString *documentsDirectory = [paths objectAtIndex:0];
   NSString* path = [documentsDirectory stringByAppendingPathComponent:@"myfile.csv"];
   
   [[NSFileManager defaultManager] createFileAtPath: path contents:nil attributes:nil];
   NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
   
   for(int i = 0; i < [locales count]; i++)
   {
      NSString* writeString = [NSString stringWithFormat:@"%@,%@\n",
                               [locales objectAtIndex:i],
                               [[NSLocale currentLocale] displayNameForKey:NSLocaleIdentifier value:[locales objectAtIndex:i]]];
      [handle writeData:[writeString dataUsingEncoding:NSUTF8StringEncoding]];
   }
*/
   
   return YES;
}

- (void)handleTeakNotification:(NSNotification*)notification
{
   NSDictionary* teakReward = [notification.userInfo objectForKey:@"teakReward"];
   NSDictionary* teakDeepLinkPath = [notification.userInfo objectForKey:@"teakDeepLinkPath"];
   NSDictionary* teakDeepLinkQueryParameters = [notification.userInfo objectForKey:@"teakDeepLinkQueryParameters"];
   NSLog(@"TEAK TOLD US ABOUT A NOTIFICATION, THANKS TEAK!\n%@\n%@\n%@", teakReward, teakDeepLinkPath, teakDeepLinkQueryParameters);
}

- (void)application:(UIApplication *)application didRegisterUserNotificationSettings:(UIUserNotificationSettings *)notificationSettings
{
   //register to receive notifications
   [application registerForRemoteNotifications];
}

- (void)applicationWillResignActive:(UIApplication *)application {
   // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
   // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
   NSLog(@"applicationWillResignActive:");
}

- (void)applicationDidEnterBackground:(UIApplication *)application {

}

- (void)applicationWillEnterForeground:(UIApplication *)application {
   // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
   NSLog(@"applicationWillEnterForeground:");
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
   
}

- (void)applicationWillTerminate:(UIApplication *)application {
   // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
