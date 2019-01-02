#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef void (^TeakLinkBlock)(NSDictionary* _Nonnull parameters);

@interface TeakLink : NSObject

+ (void)registerRoute:(nonnull NSString*)route name:(nonnull NSString*)name description:(nonnull NSString*)description block:(nonnull TeakLinkBlock)block;

+ (nonnull NSArray*)routeNamesAndDescriptions;

@end
