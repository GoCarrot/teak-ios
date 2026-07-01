#import <Foundation/Foundation.h>

@interface TeakUserConfiguration : NSObject <NSCopying>

/**
 * The email address for the current user.
 */
@property (copy, nonatomic) NSString* _Nullable email;

/**
 * The Facebook id for the current user.
 */
@property (copy, nonatomic) NSString* _Nullable facebookId;

/**
 * Opt this user out of Facebook access token collection.
 *
 * @deprecated Has no effect unless ``TeakSDK5Behaviors`` has been set to false in your
 * Info.plist; as of SDK 4.2.0, Teak no longer automatically collects the Facebook access token
 * by default.
 */
@property (nonatomic) BOOL optOutFacebook __deprecated_msg("Has no effect unless TeakSDK5Behaviors is set to false; Teak no longer auto-collects the Facebook access token by default.");

/**
 * Opt this user out of IDFA (advertising identifier) collection.
 */
@property (nonatomic) BOOL optOutIdfa;

/**
 * Opt this user out of Push Key (push token) collection.
 *
 * If you opt this user out, Teak will no longer be able to send Local Notifications or Push
 * Notifications for this user.
 */
@property (nonatomic) BOOL optOutPushKey;

- (nonnull NSDictionary*)to_h;

+ (nonnull TeakUserConfiguration*)fromDictionary:(nonnull NSDictionary*)dictionary;
@end
