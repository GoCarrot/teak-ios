#import "TeakEvent.h"
#import <Foundation/Foundation.h>

@class Teak;

@interface TeakIntegrationChecker : NSObject <TeakEventHandler>

+ (nonnull TeakIntegrationChecker*)checkIntegrationForTeak:(nonnull Teak*)teak;

- (void)reportError:(nonnull NSString*)description forCategory:(nonnull NSString*)category;

@end
