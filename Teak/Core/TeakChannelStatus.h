#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* _Nonnull const TeakChannelStatusOptOut;
extern NSString* _Nonnull const TeakChannelStatusAvailable;
extern NSString* _Nonnull const TeakChannelStatusOptIn;
extern NSString* _Nonnull const TeakChannelStatusAbsent;
extern NSString* _Nonnull const TeakChannelStatusUnknown;

@interface TeakChannelStatus : NSObject
@property (strong, nonatomic, readonly) NSString* status;
@property (nonatomic, readonly) BOOL deliveryFault;

+ (nonnull TeakChannelStatus*)unknown;

- (id)initWithDictionary:(NSDictionary*)dict;
@end

NS_ASSUME_NONNULL_END
