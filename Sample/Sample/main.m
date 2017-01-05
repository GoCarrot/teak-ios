//
//  main.m
//  Sample
//
//  Created by Pat Wilson on 2/24/16.
//  Copyright © 2016 GoCarrot Inc. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import <Teak/Teak.h>

int main(int argc, char * argv[]) {
   @autoreleasepool {
      [Teak initForApplicationId:@"1136371193060244" withClass:[AppDelegate class] andApiKey:@"1f3850f794b9093864a0778009744d03"];
      return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
   }
}
