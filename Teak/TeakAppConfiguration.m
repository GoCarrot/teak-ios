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
#import "TeakAppConfiguration.h"

#define LOG_TAG "Teak:AppConfiguration"

extern BOOL isProductionProvisioningProfile(NSString* profilePath);

@interface TeakAppConfiguration ()
@property (strong, nonatomic, readwrite) NSString* appId;
@property (strong, nonatomic, readwrite) NSString* apiKey;
@property (strong, nonatomic, readwrite) NSString* bundleId;
@property (strong, nonatomic, readwrite) NSString* appVersion;
@property (nonatomic, readwrite) BOOL isProduction;
@end

@implementation TeakAppConfiguration
- (id)initWithAppId:(nonnull NSString*)appId apiKey:(nonnull NSString*)apiKey {
   self = [super init];
   if (self) {
      self.appId = appId;
      self.apiKey = apiKey;

      @try {
         self.bundleId = [[NSBundle mainBundle] bundleIdentifier];
      } @catch (NSException* exception) {
         TeakLog(@"Failed to get Bundle Id. Teak is disabled. %@", exception);
         return nil;
      }

      @try {
         self.isProduction = isProductionProvisioningProfile([[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"]);
      } @catch (NSException* exception) {
         self.isProduction = YES;
         TeakLog("Error calling isProductionProvisioningProfile, defaulting to YES. %@", exception);
      }

      @try {
         self.appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
      } @catch (NSException *exception) {
         TeakLog(@"Error getting CFBundleShortVersionString. %@", exception);
         self.appVersion = @"unknown";
      }
   }
   return self;
}

- (NSString*)description {
   return [NSString stringWithFormat:@"<%@: %p> app-id: %@; api-key: %@; bundle-id: %@; app-version: %@; is-production: %@",
           NSStringFromClass([self class]),
           self, // @"0x%016llx"
           self.appId,
           self.apiKey,
           self.bundleId,
           self.appVersion,
           self.isProduction ? @"YES" : @"NO"];
}
@end
