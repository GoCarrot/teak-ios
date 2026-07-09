#import "TeakLaunchData.h"
#import "Teak+Internal.h"
#import "TeakHelpers.h"

extern BOOL TeakLink_WillHandleDeepLink(NSURL* deepLink);

@interface TeakLaunchDataOperation ()
@property (strong, nonatomic) NSURL* resolvedLaunchUrl;
@end

@interface TeakLaunchData ()
@property (copy, nonatomic, readwrite) NSURL* launchUrl;
@property (strong, nonatomic) NSDictionary* launchUrlQuery;

- (id)init;
- (id)initWithUrl:(NSURL*)url;
@end

@interface TeakAttributedLaunchData ()
@property (copy, nonatomic, readwrite) NSString* scheduleName;
@property (copy, nonatomic, readwrite) NSString* scheduleId;
@property (copy, nonatomic, readwrite) NSString* creativeName;
@property (copy, nonatomic, readwrite) NSString* creativeId;
@property (copy, nonatomic, readwrite) NSString* channelName;
@property (copy, nonatomic, readwrite) NSString* rewardId;
@property (copy, nonatomic, readwrite) NSURL* deepLink;
@property (copy, nonatomic, readwrite) NSString* optOutCategory;
@property (strong, nonatomic) NSDictionary* deepLinkUrlQuery;

- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

@interface TeakNotificationLaunchData ()
@property (copy, nonatomic, readwrite) NSString* sourceSendId;

- (id)initWithUrl:(NSURL*)url;
- (id)initWithTeakNotification:(TeakNotification*)teakNotification;
@end

@interface TeakRewardlinkLaunchData ()
- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink;
@end

@interface TeakLiveActivityLaunchData ()
@property (copy, nonatomic, readwrite) NSString* systemActivityId;

- (id)initWithSystemActivityId:(NSString*)systemActivityId;
@end

// Activity-resumption detection constants. These match the string values ActivityKit
// (iOS 16.2+) and WidgetKit use when iOS delivers a Live Activity tap. Declared as
// literals so the SDK doesn't have to link those frameworks on its iOS 11 deployment target.
static NSString* const kTeakNSUserActivityTypeLiveActivity = @"NSUserActivityTypeLiveActivity";
static NSString* const kTeakWGWidgetUserInfoKeyActivityID = @"WGWidgetUserInfoKeyActivityID";

/// Implementations

#define NewIfNotOld(x, y) (x == nil ? y : x)

@implementation TeakLaunchDataOperation

+ (TeakLaunchDataOperation*)fromPushNotification:(TeakNotification*)teakNotification {
  TeakNotificationLaunchData* notificationLaunchData = [[TeakNotificationLaunchData alloc] initWithTeakNotification:teakNotification];
  return [[TeakLaunchDataOperation alloc] initWithLaunchData:notificationLaunchData];
}

+ (TeakLaunchDataOperation*)fromUniversalLink:(NSURL*)url {
  TeakLaunchDataOperation* launchDataOp = [TeakLaunchDataOperation alloc];
  return [launchDataOp initWithTarget:launchDataOp selector:@selector(resolveUniversalLink:) object:url];
}

+ (TeakLaunchData*)launchDataFromUrl:(NSURL*)url withShortlink:(NSURL*)shortLink {
  NSDictionary* query = TeakGetQueryParameterDictionaryFromUrl(url);
  if (query[@"teak_rewardlink_id"]) {
    // If it has a 'teak_rewardlink_id' then it's a reward link
    return [[TeakRewardlinkLaunchData alloc] initWithUrl:url andShortLink:nil];
  } else if (query[@"teak_notif_id"]) {
    // If it has a 'teak_notif_id' then it's a notification
    return [[TeakNotificationLaunchData alloc] initWithUrl:url];
  }

  // Otherwise this is not a Teak attributed launch
  return [[TeakLaunchData alloc] initWithUrl:url];
}

// Classify a resolved universal link. When the server omits iOSPath, resolvedUrl is
// nil and we fall back to the original launch link so reward/notification attribution
// carried on the link itself isn't lost — mirroring teak-android's launchDataFromUriPair,
// which classifies the original launch link when AndroidPath is absent. Distinct from
// launchDataFromUrl:withShortlink: above: that one drops the short link (launchUrl=nil)
// for reward links, whereas here the short link is retained as launchUrl.
+ (TeakLaunchData*)launchDataFromResolvedUrl:(NSURL*)resolvedUrl shortLink:(NSURL*)shortLink {
  NSURL* attributionUrl = NewIfNotOld(resolvedUrl, shortLink);
  NSDictionary* query = TeakGetQueryParameterDictionaryFromUrl(attributionUrl);
  if (query[@"teak_rewardlink_id"]) {
    // If it has a 'teak_rewardlink_id' then it's a reward link
    return [[TeakRewardlinkLaunchData alloc] initWithUrl:attributionUrl andShortLink:shortLink];
  } else if (query[@"teak_notif_id"]) {
    // If it has a 'teak_notif_id' then it's a notification
    return [[TeakNotificationLaunchData alloc] initWithUrl:attributionUrl];
  }

  // Otherwise this is not a Teak attributed launch
  return [[TeakLaunchData alloc] initWithUrl:shortLink];
}

+ (TeakLaunchDataOperation*)fromOpenUrl:(NSURL*)url {
  TeakLaunchData* launchData = [TeakLaunchDataOperation launchDataFromUrl:url withShortlink:nil];
  return [[TeakLaunchDataOperation alloc] initWithLaunchData:launchData];
}

+ (TeakLaunchDataOperation*)fromLiveActivityTap:(NSString*)systemActivityId {
  TeakLog_i(@"live_activity.attribution.received", @{@"systemActivityId" : systemActivityId});
  TeakLiveActivityLaunchData* launchData = [[TeakLiveActivityLaunchData alloc] initWithSystemActivityId:systemActivityId];
  return [[TeakLaunchDataOperation alloc] initWithLaunchData:launchData];
}

+ (TeakLaunchDataOperation*)fromUserActivity:(NSUserActivity*)userActivity {
  if (userActivity == nil) return nil;

  if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
    return [TeakLaunchDataOperation fromUniversalLink:userActivity.webpageURL];
  }

  if ([userActivity.activityType isEqualToString:kTeakNSUserActivityTypeLiveActivity]) {
    NSString* systemActivityId = userActivity.userInfo[kTeakWGWidgetUserInfoKeyActivityID];
    if ([systemActivityId isKindOfClass:[NSString class]] && systemActivityId.length > 0) {
      return [TeakLaunchDataOperation fromLiveActivityTap:systemActivityId];
    }
  }

  return nil;
}

+ (TeakLaunchDataOperation*)unattributed {
  return [[TeakLaunchDataOperation alloc] initWithLaunchData:[[TeakLaunchData alloc] init]];
}

- (id)initWithLaunchData:(TeakLaunchData*)launchData {
  return [super initWithTarget:self selector:@selector(returnLaunchData:) object:launchData];
}

- (TeakLaunchData*)returnLaunchData:(TeakLaunchData*)launchData {
  return launchData;
}

- (TeakLaunchDataOperation*)updateDeepLink:(NSURL*)updatedDeepLink withLaunchLink:(NSURL*)launchLink {
  TeakLaunchData* launchData = self.result;
  if ([launchData isKindOfClass:TeakAttributedLaunchData.class]) {
    launchData = [(TeakAttributedLaunchData*)launchData updatedWithDeepLink:updatedDeepLink];
  } else {
    launchData = [TeakLaunchDataOperation launchDataFromUrl:updatedDeepLink withShortlink:launchLink];
  }

  // Run synchronously rather than via the shared operationQueue: this just wraps an
  // already-computed object (no I/O), and callers (e.g. TeakSession's
  // processAttributionAndDispatchEvents) check .finished immediately after this call
  // returns, in the same call stack as the reassignment below.
  TeakLaunchDataOperation* launchDataOperation = [[TeakLaunchDataOperation alloc] initWithLaunchData:launchData];
  [launchDataOperation start];
  return launchDataOperation;
}

// This will get run as an NSInvocationOperation
- (TeakLaunchData*)resolveUniversalLink:(NSURL*)url {
  // Resolve the universal link, wait for the NSURLSession to complete (or timeout)
  // then classify the result.
  dispatch_semaphore_t sema = dispatch_semaphore_create(0);
  [self resolveUniversalLink:url retryCount:0 thenSignal:sema];
  dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

  // resolvedLaunchUrl is set only when the server returned an iOSPath; when it's
  // absent (or the request failed) the classifier falls back to the original launch
  // link so reward/notification attribution on the link itself isn't lost.
  return [TeakLaunchDataOperation launchDataFromResolvedUrl:self.resolvedLaunchUrl shortLink:url];
}

- (void)resolveUniversalLink:(NSURL*)url retryCount:(int)retryCount thenSignal:(dispatch_semaphore_t)sema {
  // Make sure the URL we fetch is https
  NSURLComponents* components = [NSURLComponents componentsWithURL:url
                                           resolvingAgainstBaseURL:YES];
  components.scheme = @"https";
  NSURL* fetchUrl = components.URL;

  TeakLog_i(@"deep_link.request.send", [fetchUrl absoluteString]);
  // Fetch the data for the short link
  NSURLSession* session = [Teak URLSessionWithoutDelegate];
  NSURLSessionDataTask* task =
      [session dataTaskWithURL:fetchUrl
             completionHandler:^(NSData* _Nullable data, NSURLResponse* _Nullable response, NSError* _Nullable error) {
               // If we aren't already retrying, and there's any kind of error (for example iOS 12 malarky)
               // wait 1.5 seconds and retry.
               if (error != nil && retryCount < 1) {
                 __weak typeof(self) weakSelf = self;
                 double delayInSeconds = 1.5;
                 dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, delayInSeconds * NSEC_PER_SEC);
                 dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul), ^(void) {
                   [weakSelf resolveUniversalLink:url retryCount:retryCount + 1 thenSignal:sema];
                 });

                 // Bail out here so that we do not set the attribution
                 return;
               } else if (error != nil) {
                 // We already retried, and there's still an error, so log the error
                 TeakLog_e(@"deep_link.request.error", @{
                   @"url" : url.absoluteString,
                   @"error" : [error description]
                 });

                 // But don't return because we'll still send the link along as attribution
               } else {
                 TeakLog_i(@"deep_link.request.reply", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);

                 NSDictionary* reply = (NSDictionary*)[NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&error];
                 if (error == nil) {
                   NSString* iOSPath = reply[@"iOSPath"];
                   if (iOSPath != nil) {
                     NSRegularExpression* regExp = [NSRegularExpression regularExpressionWithPattern:@"^[a-zA-Z0-9+.\\-_]*:"
                                                                                             options:0
                                                                                               error:&error];

                     // Get resolved launchUrl
                     if (error != nil || [regExp numberOfMatchesInString:iOSPath
                                                                 options:0
                                                                   range:NSMakeRange(0, [iOSPath length])] == 0) {
                       self.resolvedLaunchUrl = [NSURL URLWithString:[NSString stringWithFormat:@"teak%@://%@",
                                                                                                [Teak sharedInstance].configuration.appConfiguration.appId,
                                                                                                iOSPath]];
                     } else {
                       self.resolvedLaunchUrl = [NSURL URLWithString:iOSPath];
                     }

                     TeakLog_i(@"deep_link.request.resolve", self.resolvedLaunchUrl.absoluteString);
                   } else if (reply.count > 0) {
                     // A resolved link is expected to carry an iOSPath; a well-formed
                     // response that omits it (e.g. an Android-only link) is anomalous,
                     // so report it with the URL and body to surface which links omit
                     // the key. Attribution still survives via the original launch link
                     // in launchDataFromResolvedUrl:shortLink:. The count gate skips an
                     // empty body, mirroring Android's teakData.length() > 0. (A malformed
                     // body parses to error != nil and is handled in the else below.)
                     TeakLog_e(@"deep_link.no_ios_path", @{
                       @"url" : url.absoluteString,
                       @"response" : [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                     });
                   }
                 } else {
                   TeakLog_e(@"deep_link.json.error", @{
                     @"url" : url.absoluteString,
                     @"error" : [error description]
                   });
                 }
               }

               // Signal, even if it ultimately failed
               dispatch_semaphore_signal(sema);
             }];
  [task resume];
}

@end

@implementation TeakLaunchData

- (id)init {
  return [self initWithUrl:nil];
}

- (id)initWithUrl:(NSURL*)url {
  self = [super init];
  if (self) {
    self.launchUrl = url;
    self.launchUrlQuery = TeakGetQueryParameterDictionaryFromUrl(url);
  }
  return self;
}

- (NSDictionary*)sessionAttribution {
  NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];

  if (self.launchUrl != nil) {
    dictionary[@"launch_link"] = TeakValueOrNSNull(self.launchUrl.absoluteString);
  }

  return dictionary;
}

- (NSDictionary*)to_h {
  NSMutableDictionary* dictionary = [[NSMutableDictionary alloc] init];
  dictionary[@"launch_link"] = TeakValueOrNSNull(self.launchUrl.absoluteString);
  return dictionary;
}

@end

@implementation TeakAttributedLaunchData

- (id)initWithUrl:(NSURL*)deepLink andShortLink:(NSURL*)shortLink {
  self = [super initWithUrl:shortLink];
  if (self) {
    self.deepLink = self.launchUrlQuery[@"teak_deep_link"] != nil ? [NSURL URLWithString:self.launchUrlQuery[@"teak_deep_link"]] : deepLink;
    self.deepLinkUrlQuery = TeakGetQueryParameterDictionaryFromUrl(self.deepLink);

    self.scheduleName = self.deepLinkUrlQuery[@"teak_schedule_name"];
    self.scheduleId = self.deepLinkUrlQuery[@"teak_schedule_id"];

    // In the non-mobile world, there is no such thing as "not a link launch" and so the
    // parameter names are different to properly differentiate session source
    self.creativeName = self.deepLinkUrlQuery[@"teak_creative_name"];
    if (self.creativeName == nil) {
      self.creativeName = self.deepLinkUrlQuery[@"teak_rewardlink_name"];
    }
    self.creativeId = self.deepLinkUrlQuery[@"teak_creative_id"];
    if (self.creativeId == nil) {
      self.creativeId = self.deepLinkUrlQuery[@"teak_rewardlink_id"];
    }

    self.channelName = self.deepLinkUrlQuery[@"teak_channel_name"];
    self.rewardId = self.deepLinkUrlQuery[@"teak_reward_id"];
    self.optOutCategory = self.deepLinkUrlQuery[@"teak_opt_out_category"];
  }
  return self;
}

- (id)initWithTeakNotification:(TeakNotification*)teakNotification {
  self = [super initWithUrl:[NSURL URLWithString:teakNotification.teakDeepLink]];
  if (self) {
    self.scheduleName = teakNotification.teakScheduleName;
    self.scheduleId = teakNotification.teakScheduleId;
    self.creativeName = teakNotification.teakCreativeName;
    self.creativeId = teakNotification.teakCreativeId;
    self.channelName = teakNotification.teakChannelName;
    self.rewardId = teakNotification.teakRewardId;
    self.deepLink = self.launchUrl; // 'teakNotification.teakDeepLink', resolved by call to super
    self.deepLinkUrlQuery = TeakGetQueryParameterDictionaryFromUrl(self.deepLink);
    self.optOutCategory = teakNotification.teakOptOutCategory;
  }
  return self;
}

- (id)initWithAttributedLaunchData:(TeakAttributedLaunchData*)oldLaunchData andUpdatedDeepLink:(NSURL*)updatedDeepLink {
  self = [super initWithUrl:oldLaunchData.launchUrl];
  if (self) {
    // Use initWithUrl:andShortLink: so newLaunchData's teak_* fields get parsed
    // from the enriched URL — the parent's initWithUrl: doesn't touch them,
    // which would leave NewIfNotOld(old, nil) returning old in every slot and
    // defeat the purpose of the enrichment merge.
    TeakAttributedLaunchData* newLaunchData = [[TeakAttributedLaunchData alloc] initWithUrl:updatedDeepLink andShortLink:nil];
    self.scheduleName = NewIfNotOld(oldLaunchData.scheduleName, newLaunchData.scheduleName);
    self.scheduleId = NewIfNotOld(oldLaunchData.scheduleId, newLaunchData.scheduleId);
    self.creativeName = NewIfNotOld(oldLaunchData.creativeName, newLaunchData.creativeName);
    self.creativeId = NewIfNotOld(oldLaunchData.creativeId, newLaunchData.creativeId);
    self.rewardId = NewIfNotOld(oldLaunchData.rewardId, newLaunchData.rewardId);
    self.channelName = NewIfNotOld(oldLaunchData.channelName, newLaunchData.channelName);
    self.deepLink = updatedDeepLink;
    self.optOutCategory = NewIfNotOld(oldLaunchData.optOutCategory, newLaunchData.optOutCategory);
    self.deepLinkUrlQuery = TeakGetQueryParameterDictionaryFromUrl(self.deepLink);
  }
  return self;
}

- (NSDictionary*)sessionAttribution {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super sessionAttribution];

  if (self.deepLink != nil) {
    dictionary[@"deep_link"] = self.deepLink.absoluteString;

    // Add any query parameter that starts with 'teak_' to the launch attribution dictionary
    for (NSString* key in self.deepLinkUrlQuery) {
      if ([key hasPrefix:@"teak_"]) {
        dictionary[key] = self.deepLinkUrlQuery[key];
      }
    }
  }

  return dictionary;
}

- (NSDictionary*)to_h {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super to_h];
  dictionary[@"teakScheduleName"] = TeakValueOrNSNull(self.scheduleName);
  dictionary[@"teakScheduleId"] = TeakValueOrNSNull(self.scheduleId);
  dictionary[@"teakCreativeName"] = TeakValueOrNSNull(self.creativeName);
  dictionary[@"teakCreativeId"] = TeakValueOrNSNull(self.creativeId);
  dictionary[@"teakRewardId"] = TeakValueOrNSNull(self.rewardId);
  dictionary[@"teakChannelName"] = TeakValueOrNSNull(self.channelName);
  dictionary[@"teakDeepLink"] = TeakLink_WillHandleDeepLink(self.launchUrl) ? self.launchUrl.absoluteString : [NSNull null];
  dictionary[@"teakOptOutCategory"] = TeakValueOrNSNull(self.optOutCategory);
  return dictionary;
}

- (TeakLaunchData*)updatedWithDeepLink:(NSURL*)updatedDeepLink {
  return [[[self class] alloc] initWithAttributedLaunchData:self andUpdatedDeepLink:updatedDeepLink];
}

@end

@implementation TeakNotificationLaunchData

- (id)initWithTeakNotification:(TeakNotification*)teakNotification {
  self = [super initWithTeakNotification:teakNotification];
  if (self) {
    self.sourceSendId = teakNotification.teakNotifId;
  }
  return self;
}

- (id)initWithUrl:(NSURL*)url {
  self = [super initWithUrl:url andShortLink:nil];
  if (self) {
    self.sourceSendId = self.deepLinkUrlQuery[@"teak_notif_id"];
  }
  return self;
}

- (id)initWithAttributedLaunchData:(TeakNotificationLaunchData*)oldLaunchData andUpdatedDeepLink:(NSURL*)updatedDeepLink {
  self = [super initWithAttributedLaunchData:oldLaunchData andUpdatedDeepLink:updatedDeepLink];
  if (self) {
    self.sourceSendId = NewIfNotOld(oldLaunchData.sourceSendId, self.deepLinkUrlQuery[@"teak_notif_id"]);
  }
  return self;
}

- (NSDictionary*)sessionAttribution {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super sessionAttribution];
  dictionary[@"teak_notif_id"] = self.sourceSendId;
  return dictionary;
}

- (NSDictionary*)to_h {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super to_h];
  dictionary[@"teakNotifId"] = TeakValueOrNSNull(self.sourceSendId);
  return dictionary;
}

@end

@implementation TeakRewardlinkLaunchData

- (id)initWithUrl:(NSURL*)url andShortLink:(NSURL*)shortLink {
  self = [super initWithUrl:url andShortLink:shortLink];
  if (self) {
    // Nothing right now
  }
  return self;
}

@end

@implementation TeakLiveActivityLaunchData

- (id)initWithSystemActivityId:(NSString*)systemActivityId {
  self = [super initWithUrl:nil andShortLink:nil];
  if (self) {
    self.systemActivityId = systemActivityId;
  }
  return self;
}

- (id)initWithAttributedLaunchData:(TeakLiveActivityLaunchData*)oldLaunchData andUpdatedDeepLink:(NSURL*)updatedDeepLink {
  self = [super initWithAttributedLaunchData:oldLaunchData andUpdatedDeepLink:updatedDeepLink];
  if (self) {
    self.systemActivityId = oldLaunchData.systemActivityId;
  }
  return self;
}

- (NSDictionary*)sessionAttribution {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super sessionAttribution];
  dictionary[@"teak_live_activity_id"] = TeakValueOrNSNull(self.systemActivityId);
  return dictionary;
}

- (NSDictionary*)to_h {
  NSMutableDictionary* dictionary = (NSMutableDictionary*)[super to_h];
  dictionary[@"teakSystemActivityId"] = TeakValueOrNSNull(self.systemActivityId);
  return dictionary;
}

@end
