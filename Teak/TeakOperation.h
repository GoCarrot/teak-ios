#import <Foundation/Foundation.h>

@interface TeakOperationResult : NSObject
@property (nonatomic) BOOL error;
@property (strong, nonatomic) NSDictionary* _Nullable errors;

- (nonnull NSDictionary*)toDictionary;
@end

@interface TeakOperationChannelStateResult : TeakOperationResult
@property (strong, nonatomic) NSString* _Nonnull state;
@property (strong, nonatomic) NSString* _Nonnull channel;
@end

@interface TeakOperationNotificationResult : TeakOperationResult
@property (strong, nonatomic) NSString* _Nonnull scheduleId;
@end

@interface TeakOperation : NSInvocationOperation

+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint replyParser:(nullable id _Nullable (NS_SWIFT_SENDABLE ^)(NSDictionary* _Nonnull reply))replyParser;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload replyParser:(nullable id _Nullable (NS_SWIFT_SENDABLE ^)(NSDictionary* _Nonnull))replyParser;

@end
