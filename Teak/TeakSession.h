#import "TeakEvent.h"
#import "TeakState.h"
#import "TeakUserProfile.h"
#import <UIKit/UIKit.h>

@class TeakSession;
@class TeakNotification;
@class TeakAppConfiguration;
@class TeakDeviceConfiguration;
@class TeakRemoteConfiguration;
@class TeakLaunchDataOperation;
@class TeakChannelStatus;

extern NSString* _Nonnull const TeakOptedIn;
extern NSString* _Nonnull const TeakOptedOut;
extern NSString* _Nonnull const TeakAvailable;

typedef void (^UserIdReadyBlock)(TeakSession* _Nonnull);

@interface TeakSession : NSObject <TeakEventHandler>
@property (strong, nonatomic, readonly) TeakAppConfiguration* _Nonnull appConfiguration;
@property (strong, nonatomic, readonly) TeakDeviceConfiguration* _Nonnull deviceConfiguration;
@property (strong, nonatomic, readonly) TeakRemoteConfiguration* _Nonnull remoteConfiguration;
@property (strong, nonatomic, readonly) NSString* _Nullable userId;
@property (strong, nonatomic, readwrite) NSString* _Nullable email;
@property (strong, nonatomic, readonly) NSString* _Nullable facebookId;
@property (strong, nonatomic, readonly) NSString* _Nonnull sessionId;
@property (strong, nonatomic, readonly) TeakState* _Nonnull currentState;
@property (strong, nonatomic, readonly) TeakUserProfile* _Nonnull userProfile;
@property (strong, nonatomic, readonly) TeakChannelStatus* _Nonnull emailStatus;
@property (strong, nonatomic, readonly) TeakChannelStatus* _Nonnull pushStatus;
@property (strong, nonatomic, readonly) TeakChannelStatus* _Nonnull smsStatus;
@property (strong, nonatomic, readonly) NSDictionary* _Nullable additionalData;

DeclareTeakState(Created);
DeclareTeakState(Configured);
DeclareTeakState(IdentifyingUser);
DeclareTeakState(UserIdentified);
DeclareTeakState(Expiring);
DeclareTeakState(Expired);

+ (nullable TeakSession*)currentSessionOrNil;

+ (void)registerStaticEventListeners;

+ (void)whenUserIdIsReadyRun:(nonnull UserIdReadyBlock)block;
+ (void)whenUserIdIsOrWasReadyRun:(nonnull UserIdReadyBlock)block;

+ (void)didLaunchWithData:(nonnull TeakLaunchDataOperation*)launchData;
@end
