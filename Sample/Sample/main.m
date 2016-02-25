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
      [Teak initForApplicationId:@"284742164932592" withClass:[AppDelegate class] andSecret:@"0a1244665e7adcd8a4106a055795952a"];
      return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
   }
}
