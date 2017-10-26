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

#import "TeakCore.h"
#import "TeakRequest.h"
#import "TeakSession.h"
#import "TrackEventEvent.h"

@implementation TeakCore

- (id)initForSomething:(id _Nullable)foo {
  self = [super init];
  if (self) {
    [TeakEvent addEventHandler:self];

    // TODO: Would be great to have a better way of doing this
    [TeakSession registerStaticEventListeners];
  }
  return self;
}

- (void)dealloc {
  [TeakEvent removeEventHandler:self];
}

- (void)handleEvent:(TeakEvent* _Nonnull)event {
  if (event.type == TrackedEvent) {
    [TeakSession whenUserIdIsReadyRun:^(TeakSession* session) {
      TeakRequest* request = [[TeakRequest alloc]
          initWithSession:session
              forEndpoint:@"/me/events"
              withPayload:((TrackEventEvent*)event).payload
                 callback:nil];
      [request send];
    }];
  }
}

@end
