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
#import "Teak+Internal.h"

extern BOOL isProductionProvisioningProfile(NSString* profilePath);

@interface TeakAppConfiguration ()
@property (strong, nonatomic, readwrite) NSString* appId;
@property (strong, nonatomic, readwrite) NSString* apiKey;
@property (strong, nonatomic, readwrite) NSString* bundleId;
@property (strong, nonatomic, readwrite) NSString* appVersion;
@property (strong, nonatomic, readwrite) NSSet*    urlSchemes;
@property (nonatomic, readwrite) BOOL isProduction;
@end

@implementation TeakAppConfiguration
- (id)initWithAppId:(nonnull NSString*)appId apiKey:(nonnull NSString*)apiKey {
   self = [super init];
   if (self) {
      self.appId = appId;
      self.apiKey = apiKey;

      // By default we listen to teakXXXXXX and fbXXXXXX URL schemes
      self.urlSchemes = [NSSet setWithObjects:
                         [NSString stringWithFormat:@"teak%@", self.appId],
                         [NSString stringWithFormat:@"fb%@", self.appId], nil];

      @try {
         self.bundleId = [[NSBundle mainBundle] bundleIdentifier];
      } @catch (NSException* exception) {
         [NSException raise:NSObjectNotAvailableException format:@"Failed to get Bundle Id."];
         return nil;
      }

      teak_try {
         self.isProduction = isProductionProvisioningProfile([[NSBundle mainBundle] pathForResource:@"embedded" ofType:@"mobileprovision"]);
      } teak_catch_report

      self.appVersion = @"unknown";
      teak_try {
         self.appVersion = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleShortVersionString"];
      } teak_catch_report
   }
   return self;
}

- (NSDictionary*)to_h {
   return @{
      @"appId" : self.appId,
      @"apiKey" : self.apiKey,
      @"bundleId" : self.bundleId,
      @"appVersion" : self.appVersion,
      @"isProduction" : self.isProduction ? @YES : @NO
   };
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
