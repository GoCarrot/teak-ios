#import <Foundation/Foundation.h>

@interface TeakOperationResult : NSObject
@property (nonatomic, readonly) BOOL error;
@property (nonatomic, strong, readonly) NSString* _Nonnull status;
@property (strong, nonatomic, readonly) NSDictionary* _Nullable errors;

- (nonnull TeakOperationResult*)initWithStatus:(nullable NSString*)status andErrors:(nullable NSDictionary*)errors;
- (BOOL)error;
- (nonnull NSDictionary*)toDictionary;
@end

@interface TeakOperationChannelStateResult : TeakOperationResult
@property (strong, nonatomic) NSString* _Nonnull state;
@property (strong, nonatomic) NSString* _Nonnull channel;
@end

@interface TeakOperationCategoryStateResult : TeakOperationChannelStateResult
@property (strong, nonatomic) NSString* _Nonnull category;
@end

@interface TeakOperationNotificationResult : TeakOperationResult
@property (strong, nonatomic) NSArray* _Nonnull scheduleIds;
@end

@interface TeakOperation : NSInvocationOperation

+ (nonnull TeakOperation*)withResult:(nonnull id)result;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint replyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull reply))replyParser;
+ (nonnull TeakOperation*)forEndpoint:(nonnull NSString*)endpoint withPayload:(nonnull NSDictionary*)payload replyParser:(nullable id _Nullable (^)(NSDictionary* _Nonnull))replyParser;

@end
