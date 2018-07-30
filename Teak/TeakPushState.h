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

#import <UIKit/UIKit.h>

#import "TeakEvent.h"
#import "TeakState.h"

@interface TeakPushState : NSObject <TeakEventHandler>

DeclareTeakState(Unknown);
DeclareTeakState(Provisional);
DeclareTeakState(Authorized);
DeclareTeakState(Denied);

- (NSInvocationOperation* _Nonnull)currentPushState;
- (void)determineCurrentPushStateWithCompletionHandler:(void (^_Nonnull)(TeakState* _Nonnull))completionHandler;
- (nonnull NSDictionary*)to_h;

@end