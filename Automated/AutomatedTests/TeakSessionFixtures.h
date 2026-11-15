#import <Foundation/Foundation.h>

@class TeakSession;

/// Builds the mocked session that tests of TeakRequest and its subclasses need: enough
/// app, device and remote configuration for a request to construct and sign its payload.
@interface TeakSessionFixtures : NSObject

/// A mocked session whose remote configuration returns `endpointConfigurations`
/// (hostname -> endpoint -> batch/retry settings), the same shape TeakRemoteConfiguration serves.
/// Pass @{} for a request that sends immediately, doesn't batch and doesn't retry on a schedule.
+ (nonnull TeakSession*)mockSessionWithEndpointConfigurations:(nonnull NSDictionary*)endpointConfigurations;

@end
