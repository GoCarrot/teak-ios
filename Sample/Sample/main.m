/* Teak Example -- Copyright (C) 2016 GoCarrot Inc.
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

#import "AppDelegate.h"
#import <UIKit/UIKit.h>

// Step 1:
// Import Teak into the main.m file to use the initialization method.
#import <Teak/Teak.h>

int main(int argc, char* argv[]) {
  @autoreleasepool {
    // Step 2:
    // Initialize Teak inside the @autoreleasepool but before UIApplicationMain() is called.
    [Teak initForApplicationId:@"613659812345256"                    // Use your Teak Application Id here.
                     withClass:[AppDelegate class]                   // Use the name of your main UIApplicationDelegate here.
                     andApiKey:@"41ff00cfd4cb85702e265aa3d5ab7858"]; // Use your Teak API Key here.

    // Continue to our AppDelegate.m file for the next steps.

    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
