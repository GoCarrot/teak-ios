// ObjC/C-only StoreKit 2 observation probes. Built as its own framework with no Swift sources,
// so `nm` on it proves the technique needs no Swift in Teak.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SK2Observer : NSObject
// Logs StoreKit's ObjC classes/protocols whose names suggest SK2 transaction plumbing.
+ (void)dumpStoreKitRuntime;
// Rebinds every loaded image's GOT slot for Transaction.finish()'s async function pointer to a C thunk.
// Returns the number of slots rebound.
+ (NSInteger)installFinishHook;
// Transaction ids seen by the finish thunk, in order.
+ (NSArray<NSNumber *> *)finishedIds;
+ (NSArray<NSString *> *)finishedJSON;
+ (void)reset;
// Rebinds GOT slots for VerificationResult<Transaction>.jwsRepresentation's getter to a wrapper.
+ (NSInteger)installJWSHook;
+ (NSArray<NSString *> *)seenJWS;
@end

NS_ASSUME_NONNULL_END
