/* Teak -- Copyright (C) 2018 GoCarrot Inc.
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

#import "TeakDataCollectionConfiguration.h"

#define kTeakEnableIDFA @"TeakEnableIDFA"
#define kTeakEnableFacebook @"TeakEnableFacebook"
#define kTeakEnablePushKey @"TeakEnablePushKey"

@interface TeakDataCollectionConfiguration ()
@property (nonatomic, readwrite) BOOL enableIDFA;
@property (nonatomic, readwrite) BOOL enableFacebookAccessToken;
@property (nonatomic, readwrite) BOOL enablePushKey;
@end

@implementation TeakDataCollectionConfiguration
- (id)init {
  self = [super init];
  if (self) {
#define IS_FEATURE_ENABLED(_feature) ([[[NSBundle mainBundle] infoDictionary] valueForKey:_feature] == nil) ? YES : [[[[NSBundle mainBundle] infoDictionary] valueForKey:_feature] boolValue]
    self.enableIDFA = IS_FEATURE_ENABLED(kTeakEnableIDFA);
    self.enableFacebookAccessToken = IS_FEATURE_ENABLED(kTeakEnableFacebook);
    self.enablePushKey = IS_FEATURE_ENABLED(kTeakEnablePushKey);
#undef IS_FEATURE_ENABLED
  }
  return self;
}
@end
