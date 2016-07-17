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

#import "TeakDebugConfiguration.h"

#define LOG_TAG "Teak:DebugConfig"

#define kForceDebugPreferencesKey @"TeakForceDebug"
#define kBugReportUrl @"https://github.com/GoCarrot/teak-ios/issues/new"

@interface TeakDebugConfiguration ()
@property (nonatomic, readwrite) BOOL forceDebug;

@property (strong, nonatomic) NSUserDefaults* userDefaults;
@end

@implementation TeakDebugConfiguration

- (id)init {
   self = [super init];
   if (self) {
      @try {
         self.userDefaults = [NSUserDefaults standardUserDefaults];
      } @catch (NSException* exception) {
         TeakLog(@"Error calling [NSUserDefaults standardUserDefaults]. %@", exception);
      }

      if (self.userDefaults == nil) {
         TeakLog(@"[NSUserDefaults standardUserDefaults] returned nil. Some debug functionality is disabled.");
      } else {
         self.forceDebug = [self.userDefaults boolForKey:kForceDebugPreferencesKey];
      }
   }
   return self;
}

- (void)setForceDebugPreference:(BOOL)forceDebug {
   if (self.userDefaults == nil) {
      TeakLog(@"[NSUserDefaults standardUserDefaults] returned nil. Setting force debug is disabled.");
   }
   else {
      @try {
         [self.userDefaults setBool:forceDebug forKey:kForceDebugPreferencesKey];
         [self.userDefaults synchronize];
         TeakLog(@"Force debug is now %s, please re-start the app.", forceDebug ? "enabled" : "disabled");
      } @catch (NSException* exception) {
         TeakLog(@"Error occurred while synchronizing userDefaults. %@", exception);
      }
      self.forceDebug = forceDebug;
   }
}

- (NSString*)description {
   return [NSString stringWithFormat:@"<%@: %@> forceDebug %@", NSStringFromClass([self class]),
           [NSString stringWithFormat:@"0x%16@", self],
           self.forceDebug ? @"YES" : @"NO"];
}
@end
