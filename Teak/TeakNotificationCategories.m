/* Teak -- Copyright (C) 2017 GoCarrot Inc.
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

#import "Teak+Internal.h"

NSDictionary* TeakNotificationCategories = nil;
NSBundle* TeakResourceBundle = nil;

NSString* TeakLocalizedStringWithDefaultValue(NSString* key, NSString* tbl, NSBundle* bundle, NSString* val, NSString* comment) {
  NSString* ret = NSLocalizedStringWithDefaultValue(key, tbl, bundle, val, comment);
  return [ret length] > 0 ? ret : val;
}

__attribute__((constructor)) void teak_init_notification_categories() {
  @try {
    NSURL* bundleUrl = [[NSBundle mainBundle] URLForResource:@"TeakResources" withExtension:@"bundle"];
    TeakResourceBundle = [NSBundle bundleWithURL:bundleUrl];
  } @catch (NSException* ignored) {
    NSLog(@"[Teak] Resources bundle not present. Only English localization supported.");
    TeakResourceBundle = nil;
  }

  // TODO: Need CSV to handle the localization notes (comment)
  TeakNotificationCategories = @{
#error Must run 'import_notification_categories' before building
  };
}
