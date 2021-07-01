#import "TeakEvent.h"
#import <Foundation/Foundation.h>

extern NSString* _Nonnull const TeakDeviceConfiguration_NotificationDisplayState_Enabled;
extern NSString* _Nonnull const TeakDeviceConfiguration_NotificationDisplayState_Disabled;
extern NSString* _Nonnull const TeakDeviceConfiguration_NotificationDisplayState_NotDetermined;

@class TeakAppConfiguration;

@interface TeakDeviceConfiguration : NSObject <TeakEventHandler>
@property (strong, nonatomic, readonly) NSString* _Nonnull deviceId;
@property (strong, nonatomic, readonly) NSString* _Nonnull deviceModel;
@property (strong, nonatomic, readonly) NSString* _Nonnull pushToken;
@property (strong, nonatomic, readonly) NSString* _Nonnull platformString;
@property (strong, nonatomic, readonly) NSString* _Nonnull advertisingIdentifier;
@property (strong, nonatomic, readonly) NSString* _Nonnull notificationDisplayEnabled;
@property (nonatomic, readonly) BOOL limitAdTracking;
@property (nonatomic, readonly) unsigned long long phyiscalMemoryInBytes;
@property (nonatomic, readonly) NSUInteger numberOfCores;
@property (nonatomic, readonly) NSDictionary* _Nonnull displayMetrics;

- (nullable id)init;
- (nonnull NSDictionary*)to_h;
@end
