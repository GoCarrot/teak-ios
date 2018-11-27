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
#import "Teak+Internal.h"

#define kLogLocalPreferencesKey @"TeakLogLocal"
#define kLogRemotePreferencesKey @"TeakLogRemote"

@interface TeakDebugConfiguration ()
@property (nonatomic, readwrite) BOOL logLocal;
@property (nonatomic, readwrite) BOOL logRemote;

@property (strong, nonatomic) NSUserDefaults* userDefaults;
@end

@implementation TeakDebugConfiguration

- (id)init {
  self = [super init];
  if (self) {
    teak_try {
      self.userDefaults = [NSUserDefaults standardUserDefaults];
    }
    teak_catch_report;

    if (self.userDefaults == nil) {
      NSLog(@"[NSUserDefaults standardUserDefaults] returned nil. Some debug functionality is disabled.");
    } else {
      self.logLocal = [self.userDefaults boolForKey:kLogLocalPreferencesKey];
      self.logRemote = [self.userDefaults boolForKey:kLogRemotePreferencesKey];
    }
  }
  return self;
}

- (void)setLogLocal:(BOOL)logLocal logRemote:(BOOL)logRemote {
  if (self.userDefaults == nil) {
    TeakLog_e(@"debug_configuration", @"[NSUserDefaults standardUserDefaults] returned nil. Setting force debug is disabled.");
  } else {
    @try {
      [self.userDefaults setBool:logLocal forKey:kLogLocalPreferencesKey];
      [self.userDefaults setBool:logRemote forKey:kLogRemotePreferencesKey];
    } @catch (NSException* exception) {
      NSLog(@"Error occurred while writing to userDefaults. %@", exception);
    }
    self.logLocal = logLocal;
    self.logRemote = logRemote;
  }
}

- (NSString*)description {
  return [NSString stringWithFormat:@"<%@: %@> logLocal %@, logRemote %@", NSStringFromClass([self class]),
                                    [NSString stringWithFormat:@"0x%16@", self],
                                    self.logLocal ? @"YES" : @"NO", self.logRemote ? @"YES" : @"NO"];
}
@end
