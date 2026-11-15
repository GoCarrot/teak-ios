/* Teak Example -- Copyright (C) 2026 GoCarrot Inc.
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

// Named in Info.plist's scene manifest.
@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow* window;
@end

// Not in the manifest. Picked at runtime by the app delegate when launched with
// -SceneSampleRuntimeDelegate YES.
@interface RuntimeSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow* window;
@end

// Shows what Teak saw: its lifecycle callbacks and the deep links it handled.
void SceneSampleInstallStatus(void);
void SceneSampleAttachStatus(UIWindow* window);
