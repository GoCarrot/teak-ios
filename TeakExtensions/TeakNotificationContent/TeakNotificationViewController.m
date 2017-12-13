/* Teak -- Copyright (C) 2017 GoCarrot Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#import "TeakNotificationViewController.h"
#import <AVKit/AVKit.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

NSString* TeakNSStringOrNilFor(id object) {
  if (object == nil) return nil;

  NSString* ret = nil;
  @try {
    ret = ((object == nil || [object isKindOfClass:[NSString class]]) ? object : [object stringValue]);
  } @catch (NSException* ignored) {
  }
  return ret;
}

/////

@interface TeakAVPlayerView : UIView
@property (strong, nonatomic, setter=setPlayer:) AVPlayer* player;

+ (Class)layerClass;
- (void)setPlayer:(AVPlayer*)player;
@end

@implementation TeakAVPlayerView
+ (Class)layerClass {
  return [AVPlayerLayer class];
}

- (void)setPlayer:(AVPlayer*)player {
  [(AVPlayerLayer*)self.layer setPlayer:player];
  _player = player;
}
@end

/////

@interface UIImageArrayView : UIImageView
@property (strong, nonatomic, setter=setImageArray:) NSArray* imageArray;
@property (nonatomic, setter=setImageIndex:) NSUInteger imageIndex;

- (id)initWithImageArray:(NSArray*)imageArray;
- (void)setImageArray:(NSArray*)imageArray;
@end

@implementation UIImageArrayView
- (id)initWithImageArray:(NSArray*)imageArray {
  self = [super init];
  if (self) {
    self.imageArray = imageArray;
  }
  return self;
}

- (void)setImageArray:(NSArray*)imageArray {
  _imageArray = imageArray;
  self.imageIndex = 0;
}

- (void)setImageIndex:(NSUInteger)imageIndex {
  _imageIndex = imageIndex;
  self.image = self.imageArray[_imageIndex];
}
@end

/////

@interface TeakNotificationViewController () <UNNotificationContentExtension>
@property (strong, nonatomic) NSURLSession* session;
@property (strong, nonatomic) NSOperationQueue* operationQueue;
@property (strong, nonatomic) NSOperation* sessionFinishOperation;

// Video related
@property (strong, nonatomic) AVPlayer* player;
@property (strong, nonatomic) AVPlayerItem* playerItem;

// Image related
@property (strong, nonatomic) UIImage* image;

// Common parent view for whatever is in the notification.
@property (strong, nonatomic) UIView* notificationContentView;

// Configuration
@property (strong, nonatomic) NSDictionary* actions;
@property (nonatomic) BOOL autoPlay;
@property (nonatomic) BOOL loop;
@end

@implementation TeakNotificationViewController

- (void)viewDidLoad {
  [super viewDidLoad];
}

- (void)configureForNotification:(UNNotification*)notification {
  NSDictionary* aps = notification.request.content.userInfo[@"aps"];

  // Button actions, nil = just launch the app
  self.actions = aps[@"actions"];
  if (self.actions == nil || self.actions == (NSDictionary*)[NSNull null]) {
    self.actions = [[NSDictionary alloc] init];
  }

  // Video options
  self.autoPlay = (aps[@"autoplay"] == nil || aps[@"autoplay"] == [NSNull null]) ? NO : aps[@"autoplay"];
  self.loop = (aps[@"loop"] == nil || aps[@"loop"] == [NSNull null]) ? NO : aps[@"loop"];
}

- (void)didReceiveNotification:(UNNotification*)notification {
  [self configureForNotification:notification];

  self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
  self.operationQueue = [[NSOperationQueue alloc] init];
  self.sessionFinishOperation = [NSBlockOperation blockOperationWithBlock:^{
    [self.session finishTasksAndInvalidate];
  }];

  NSDictionary* aps = notification.request.content.userInfo[@"aps"];
  NSString* teakNotifId = TeakNSStringOrNilFor(aps[@"teakNotifId"]);
  NSString* teakUserId = TeakNSStringOrNilFor(aps[@"teakUserId"]);
  if ([teakNotifId length] > 0 && [teakUserId length] > 0) {
    NSOperation* metricOperation = [self sendMetricForPayload:@{
      @"user_id" : teakUserId,
      @"platform_id" : teakNotifId,
      @"network_id" : @3
    }];
    [self.sessionFinishOperation addDependency:metricOperation];
  }

  // Move this if more ops are added
  [self.operationQueue addOperation:self.sessionFinishOperation];

  // The first object of the attachments array will be displayed as the "preview" in the small view,
  // we can use any subsequent attachments differently
  UNNotificationAttachment* attachment = [notification.request.content.attachments lastObject];
  if (attachment == nil || attachment.URL == nil || ![attachment.URL startAccessingSecurityScopedResource]) return;

  if ([[attachment.URL pathExtension] isEqualToString:@"mp4"]) {
    AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:attachment.URL options:nil];
    [attachment.URL stopAccessingSecurityScopedResource];

    self.playerItem = [[AVPlayerItem alloc] initWithAsset:asset];
  } else { // if image type
    NSData* attachmentData = [[NSData alloc] initWithContentsOfURL:attachment.URL];
    [attachment.URL stopAccessingSecurityScopedResource];

    self.image = [UIImage imageWithData:attachmentData];
  }

  float scaledHeight = 0.0f;
  if (self.playerItem != nil) {
    AVAssetTrack* track = [[self.playerItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    CGSize trackSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
    float scaleRatio = self.view.frame.size.width / trackSize.width;
    scaledHeight = trackSize.height * scaleRatio;

    AVQueuePlayer* queuePlayer = [AVQueuePlayer queuePlayerWithItems:@[ self.playerItem ]];
    if (self.loop) {
      self.player = (AVPlayer*)[AVPlayerLooper playerLooperWithPlayer:queuePlayer
                                                         templateItem:self.playerItem];
    } else {
      self.player = (AVPlayer*)queuePlayer;
    }

    TeakAVPlayerView* playerView = [[TeakAVPlayerView alloc] init];
    playerView.player = self.player;
    self.notificationContentView = playerView;
  } else if (self.image != nil) {
    float imageScaleRatio = self.view.frame.size.width / (self.image.size.width * self.image.scale);
    scaledHeight = self.image.size.height * self.image.scale * imageScaleRatio;

    UIImageArrayView* imageView = [[UIImageArrayView alloc] initWithImageArray:@[ self.image ]];
    imageView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

    self.notificationContentView = imageView;
  }

  /////

  self.notificationContentView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

  self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y,
                               self.view.frame.size.width, scaledHeight);
  self.preferredContentSize = CGSizeMake(self.view.frame.size.width, scaledHeight);
  [self.view addSubview:self.notificationContentView];

  // Start video if auto-play
  if (self.autoPlay) {
    [self.player play];
  }
}

- (void)didReceiveNotificationResponse:(UNNotificationResponse*)response
                     completionHandler:(void (^)(UNNotificationContentExtensionResponseOption option))completionHandler {
  NSString* action = self.actions[response.actionIdentifier];
  if (action == nil) {
    completionHandler(UNNotificationContentExtensionResponseOptionDismissAndForwardAction);
  } else {
    [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:self.playerItem
                                                       queue:nil
                                                  usingBlock:^(NSNotification* notification) {
                                                    [[NSNotificationCenter defaultCenter] removeObserver:self];
                                                    completionHandler(UNNotificationContentExtensionResponseOptionDismissAndForwardAction);
                                                  }];
  }

  [self.player play];
}

- (NSOperation*)sendMetricForPayload:(NSDictionary*)payload {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://parsnip.gocarrot.com/notification_expanded"]];

  NSString* boundry = @"-===-httpB0unDarY-==-";

  NSMutableData* postData = [[NSMutableData alloc] init];

  for (NSString* key in payload) {
    [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
    [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", key, [payload objectForKey:key]] dataUsingEncoding:NSUTF8StringEncoding]];
  }
  [postData appendData:[[NSString stringWithFormat:@"--%@--\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];

  [request setHTTPMethod:@"POST"];
  [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)[postData length]] forHTTPHeaderField:@"Content-Length"];
  [request setHTTPBody:postData];
  NSString* charset = (NSString*)CFStringConvertEncodingToIANACharSetName(CFStringConvertNSStringEncodingToEncoding(NSUTF8StringEncoding));
  [request setValue:[NSString stringWithFormat:@"multipart/form-data; charset=%@; boundary=%@", charset, boundry] forHTTPHeaderField:@"Content-Type"];

  NSOperation* metricOperation = [NSBlockOperation blockOperationWithBlock:^{}];

  NSURLSessionUploadTask* uploadTask =
      [self.session uploadTaskWithRequest:request
                                 fromData:nil
                        completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
                          [self.operationQueue addOperation:metricOperation];
                        }];
  [uploadTask resume];
  return metricOperation;
}

@end
