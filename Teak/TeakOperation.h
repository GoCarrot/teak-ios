#import <Foundation/Foundation.h>

@interface TeakOperationResult : NSObject
@property (nonatomic, readonly) BOOL error;
@property (strong, nonatomic, readonly) NSDictionary* _Nullable errors;

- (nonnull NSDictionary*)toDictionary;
@end

@interface TeakOperationChannelStateResult : TeakOperationResult
@property (strong, nonatomic, readonly) NSString* _Nonnull state;
@property (strong, nonatomic, readonly) NSString* _Nonnull channel;
@end

@interface TeakOperation : NSInvocationOperation

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload;

@end
