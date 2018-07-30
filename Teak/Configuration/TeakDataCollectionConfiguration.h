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

#import <Foundation/Foundation.h>

@interface TeakDataCollectionConfiguration : NSObject

@property (nonatomic, readonly) BOOL enableIDFA;
@property (nonatomic, readonly) BOOL enableFacebookAccessToken;
@property (nonatomic, readonly) BOOL enablePushKey;

- (NSDictionary*)to_h;

// Future-Pat: No, we do *not* want to ever configure what data is collected as the result of a server call,
//             because that would change us from being a "data processor" to a "data controller" under the GDPR
- (void)addConfigurationFromDeveloper:(NSArray*)optOutList;

@end