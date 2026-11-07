#import <UIKit/UIKit.h>
#import <Teak/Teak.h>
#import "AppDelegate.h"

int main(int argc, char* argv[]) {
  @autoreleasepool {
    [Teak initForApplicationId:@"613659812345256" withClass:[AppDelegate class] andApiKey:@"41ff00cfd4cb85702e265aa3d5ab7858"];
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
