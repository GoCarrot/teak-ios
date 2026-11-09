/* Teak Example -- Copyright (C) 2026 GoCarrot Inc.
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

#import "SceneDelegate.h"
#import <Teak/Teak.h>

static NSInteger sBecameActive = 0;
static NSInteger sResignedActive = 0;
static NSInteger sDeepLinks = 0;
static NSString* sLastDeepLink = @"none";
static NSString* const SceneSampleStatusChanged = @"SceneSampleStatusChanged";

static NSString* SceneSampleStatusText(void) {
  return [NSString stringWithFormat:@"Teak lifecycle: active %ld, resign %ld\nTeak deep links: %ld\nLast: %@",
                                    (long)sBecameActive, (long)sResignedActive, (long)sDeepLinks, sLastDeepLink];
}

void SceneSampleInstallStatus(void) {
  [Teak sharedInstance].logListener = ^(NSString* event, NSString* level, NSDictionary* payload) {
    NSDictionary* data = payload[@"event_data"];
    dispatch_async(dispatch_get_main_queue(), ^{
      if ([event isEqualToString:@"lifecycle"]) {
        NSString* callback = data[@"callback"];
        if ([callback isEqualToString:@"applicationDidBecomeActive:"]) sBecameActive++;
        else if ([callback isEqualToString:@"applicationWillResignActive:"]) sResignedActive++;
        else return;
      } else if ([event isEqualToString:@"deep_link.handled"]) {
        sDeepLinks++;
        sLastDeepLink = data[@"url"] ?: @"?";
      } else {
        return;
      }
      NSLog(@"SceneSample: %@", [SceneSampleStatusText() stringByReplacingOccurrencesOfString:@"\n" withString:@" | "]);
      [[NSNotificationCenter defaultCenter] postNotificationName:SceneSampleStatusChanged object:nil];
    });
  };
}

void SceneSampleAttachStatus(UIWindow* window) {
  UIView* root = window.rootViewController.view;
  UILabel* label = [[UILabel alloc] init];
  label.numberOfLines = 0;
  label.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
  label.backgroundColor = [[UIColor systemBackgroundColor] colorWithAlphaComponent:0.85];
  label.translatesAutoresizingMaskIntoConstraints = NO;
  [root addSubview:label];
  [NSLayoutConstraint activateConstraints:@[
    [label.leadingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.leadingAnchor constant:8],
    [label.trailingAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.trailingAnchor constant:-8],
    [label.bottomAnchor constraintEqualToAnchor:root.safeAreaLayoutGuide.bottomAnchor constant:-8],
  ]];

  NSString* delegateName = NSStringFromClass([window.windowScene.delegate class]);
  void (^update)(void) = ^{
    label.text = [NSString stringWithFormat:@"Scene delegate: %@\n%@", delegateName, SceneSampleStatusText()];
  };
  update();
  [[NSNotificationCenter defaultCenter] addObserverForName:SceneSampleStatusChanged
                                                    object:nil
                                                     queue:[NSOperationQueue mainQueue]
                                                usingBlock:^(NSNotification* note) {
                                                  update();
                                                }];
}

// The window comes from UISceneStoryboardFile; these only attach the status label. Neither class
// implements scene:openURLContexts: or scene:continueUserActivity:, like many migrated apps.

@implementation SceneDelegate

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions {
  NSLog(@"SceneSample: %@ willConnect, %lu launch URL(s)", NSStringFromClass([self class]), (unsigned long)connectionOptions.URLContexts.count);
  SceneSampleAttachStatus(self.window);
}

@end

@implementation RuntimeSceneDelegate

- (void)scene:(UIScene*)scene willConnectToSession:(UISceneSession*)session options:(UISceneConnectionOptions*)connectionOptions {
  NSLog(@"SceneSample: %@ willConnect, %lu launch URL(s)", NSStringFromClass([self class]), (unsigned long)connectionOptions.URLContexts.count);
  if (self.window == nil) {
    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene*)scene];
    self.window.rootViewController = [[UIStoryboard storyboardWithName:@"Main" bundle:nil] instantiateInitialViewController];
    [self.window makeKeyAndVisible];
  }
  SceneSampleAttachStatus(self.window);
}

@end
