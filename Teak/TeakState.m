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

#import "TeakState.h"

@interface TeakState ()
@property (strong, nonatomic, readwrite) NSString* name;

@property (strong, nonatomic) NSArray* allowedTransitions;
@end

@implementation TeakState

DefineTeakState(Invalid, (@[]))

- (id)initWithName:(nonnull NSString*)name allowedTransitions:(nonnull NSArray*)allowedTransitions {
   self = [super init];
   if (self) {
      self.name = name;
      for (id state in allowedTransitions) {
         if (![state isKindOfClass:[NSString class]]) {
            [NSException raise:NSInvalidArgumentException format:@"Non-NSString element of allowedTransitions. Returning nil."];
            return nil;
         }
      }
      self.allowedTransitions = allowedTransitions;
   }
   return self;
}

- (BOOL)canTransitionToState:(nonnull TeakState*)nextState {
   if (nextState == [TeakState Invalid]) return YES;
   for (NSString* stateName in self.allowedTransitions) {
      if ([stateName isEqualToString:nextState.name]) return YES;
   }
   return NO;
}

- (NSString*)description {
   return [NSString stringWithFormat:@"<%@: %p> name: %@", NSStringFromClass([self class]), self, self.name];
}
@end
