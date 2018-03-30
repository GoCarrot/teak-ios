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
#import "TeakUserProfile.h"
#import "Teak+Internal.h"
#import "TeakSession.h"

@interface TeakUserProfile ()
@property (strong, nonatomic) NSMutableDictionary* stringAttributes;
@property (strong, nonatomic) NSMutableDictionary* numberAttributes;
@property (strong, nonatomic) NSString* context;
@property (strong, nonatomic) dispatch_block_t scheduledBlock;
@end

@implementation TeakUserProfile

- (TeakUserProfile*)initForSession:(TeakSession*)session withDictionary:(NSDictionary*)dictionary {
  self = [super initWithSession:session forHostname:@"gocarrot.com" withEndpoint:@"/me/profile" withPayload:@{} callback:nil addCommonPayload:YES];
  if (self) {
    self.stringAttributes = [dictionary[@"string_attributes"] mutableCopy];
    self.numberAttributes = [dictionary[@"number_attributes"] mutableCopy];
    self.context = [dictionary[@"context"] copy];
  }
  return self;
}

- (void)setNumericAttribute:(double)d_value forKey:(NSString*)key {
  NSNumber* value = [NSNumber numberWithDouble:d_value];
  if (![value isEqualToNumber:self.numberAttributes[key]]) {
    [self setAttribute:value forKey:key inDictionary:self.numberAttributes];
  }
}

- (void)setStringAttribute:(NSString*)value forKey:(NSString*)key {
  if (![value isEqualToString:self.stringAttributes[key]]) {
    [self setAttribute:value forKey:key inDictionary:self.stringAttributes];
  }
}

- (void)setAttribute:(id)value forKey:(NSString*)key inDictionary:(NSMutableDictionary*)dictionary {
  // Future-Pat: *only* check vs nil here, not NSNull. NSNull is fine.
  if (dictionary[key] != nil) {
    if (self.scheduledBlock != nil) {
      dispatch_block_cancel(self.scheduledBlock);
    }

    dispatch_async([Teak operationQueue], ^{
      dictionary[key] = value;

      self.scheduledBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        [self send];
      });

      dispatch_time_t delayTime = dispatch_time(DISPATCH_TIME_NOW, self.batch.time * NSEC_PER_SEC);
      dispatch_after(delayTime, [Teak operationQueue], self.scheduledBlock);
    });
  }
}

- (void)send {
  // No scheduledBlock means no pending update
  if (self.scheduledBlock != nil) {
    dispatch_block_cancel(self.scheduledBlock);

    NSMutableDictionary* payload = [self.payload mutableCopy];
    [payload addEntriesFromDictionary:@{
      @"string_attributes" : [self.stringAttributes copy],
      @"number_attributes" : [self.numberAttributes copy],
      @"context" : [self.context copy]
    }];
    self.payload = payload;

    [super send];
  }
}

@end
