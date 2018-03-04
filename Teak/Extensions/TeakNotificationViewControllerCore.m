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

#import <AVKit/AVKit.h>
#import <Teak/TeakNotificationViewControllerCore.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

/////
// For XCode 8.x
#import <AVFoundation/AVFoundation.h>

/////

extern UIImage* UIImage_animatedImageWithAnimatedGIFData(NSData* data);

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

@interface TeakNotificationViewControllerCore () <UNNotificationContentExtension>
@property (strong, nonatomic) NSURLSession* session;
@property (strong, nonatomic) NSOperationQueue* operationQueue;
@property (strong, nonatomic) NSOperation* sessionFinishOperation;
@property (strong, nonatomic) NSArray* assets;
@property (strong, nonatomic) NSDictionary* notificationUserData;

// Video related
@property (strong, nonatomic) AVPlayerLooper* playerLooper;
@property (strong, nonatomic) AVPlayer* videoPlayer;

// Common parent view for whatever is in the notification.
@property (strong, nonatomic) UIView* notificationContentView;

// Configuration
@property (strong, nonatomic) NSDictionary* actions;
@property (nonatomic) BOOL autoPlay;
@property (nonatomic) BOOL loopInitialContent;
@property (nonatomic, copy) void (^prepareContentView)(void);

// Input
@property (nonatomic) dispatch_once_t inputHandlerDispatchOnce;
@end

@implementation TeakNotificationViewControllerCore

- (void)viewDidLoad {
  [super viewDidLoad];
}

- (void)configureForNotification:(UNNotification*)notification {
  self.notificationUserData = notification.request.content.userInfo[@"aps"];

  // Button actions, nil = just launch the app
  self.actions = self.notificationUserData[@"playableActions"];
  if (self.actions == nil || self.actions == (NSDictionary*)[NSNull null]) {
    self.actions = [[NSDictionary alloc] init];
  }

  // Video options
  self.autoPlay = TeakBoolFor(self.notificationUserData[@"autoplay"]);
  self.loopInitialContent = TeakBoolFor(self.notificationUserData[@"loopInitialContent"]);
}

- (void)initURLSession {
  self.session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration ephemeralSessionConfiguration]];
  self.operationQueue = [[NSOperationQueue alloc] init];
  self.sessionFinishOperation = [NSBlockOperation blockOperationWithBlock:^{
    [self.session finishTasksAndInvalidate];
  }];
}

- (void)queueMetricSend {
  NSString* teakNotifId = TeakNSStringOrNilFor(self.notificationUserData[@"teakNotifId"]);
  NSString* teakUserId = TeakNSStringOrNilFor(self.notificationUserData[@"teakUserId"]);
  if ([teakNotifId length] > 0 && [teakUserId length] > 0) {
    NSOperation* metricOperation = [self sendMetricForPayload:@{
      @"user_id" : teakUserId,
      @"platform_id" : teakNotifId,
      @"network_id" : @3
    }];
    [self.sessionFinishOperation addDependency:metricOperation];
  }
}

- (void)createThumbnailViewForItem:(AVPlayerItem*)item atTime:(CMTime)time {
  AVAsset* asset = item.asset;
  AVAssetImageGenerator* imageGenerator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
  CGImageRef imageRef = [imageGenerator copyCGImageAtTime:time actualTime:NULL error:NULL];
  UIImage* thumbnail = [UIImage imageWithCGImage:imageRef];
  UIImageView* imageView = [[UIImageView alloc] initWithImage:thumbnail];
  float imageScaleRatio = self.view.frame.size.width / (thumbnail.size.width * thumbnail.scale);
  float scaledHeight = thumbnail.size.height * thumbnail.scale * imageScaleRatio;

  imageView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);
  [self.view insertSubview:imageView belowSubview:self.notificationContentView];
  CGImageRelease(imageRef); // CGImageRef won't be released by ARC
}

- (void)didReceiveNotification:(UNNotification*)notification {
  [self configureForNotification:notification];
  [self initURLSession];
  [self queueMetricSend];

  // Move this if more ops are added
  [self.operationQueue addOperation:self.sessionFinishOperation];

  BOOL startAssetIsImage = NO;
  NSMutableArray* buildingAssets = [[NSMutableArray alloc] init];
  NSUInteger contentIndex = [self.notificationUserData[@"content"] unsignedIntegerValue];
  for (NSUInteger i = contentIndex; i < [notification.request.content.attachments count]; i++) {
    UNNotificationAttachment* attachment = notification.request.content.attachments[i];

    // Bail if something has gone wrong with the attachments
    if (attachment == nil || attachment.URL == nil || ![attachment.URL startAccessingSecurityScopedResource]) return;

    // mp4 is video, assume everything else is an image of some type
    if ([[attachment.URL pathExtension] isEqualToString:@"mp4"]) {
      AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:attachment.URL options:nil];
      [attachment.URL stopAccessingSecurityScopedResource];
      [buildingAssets addObject:[AVPlayerItem playerItemWithAsset:asset]];
    } else { // It's an image
      NSData* attachmentData = [[NSData alloc] initWithContentsOfURL:attachment.URL];
      [attachment.URL stopAccessingSecurityScopedResource];
      UIImage* image = nil;
      if ([[attachment.URL pathExtension] isEqualToString:@"gif"]) {
        image = UIImage_animatedImageWithAnimatedGIFData(attachmentData);
      } else {
        image = [UIImage imageWithData:attachmentData];
      }
      [buildingAssets addObject:image];
      startAssetIsImage = YES;
    }
  }
  self.assets = buildingAssets;

  if (self.assets.count > 0) {
    float scaledHeight = 0.0f;
    if (startAssetIsImage) {
      UIImage* firstImage = [self.assets firstObject];
      float imageScaleRatio = self.view.frame.size.width / (firstImage.size.width * firstImage.scale);
      scaledHeight = firstImage.size.height * firstImage.scale * imageScaleRatio;

      self.notificationContentView = [[UIImageArrayView alloc] initWithImageArray:self.assets];
      self.notificationContentView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

      __weak typeof(self) weakSelf = self;
      self.prepareContentView = ^{
        __strong typeof(self) blockSelf = weakSelf;
        TeakAVPlayerView* playerView = [[TeakAVPlayerView alloc] init];
        playerView.frame = blockSelf.notificationContentView.frame;
        [blockSelf.view insertSubview:playerView aboveSubview:blockSelf.notificationContentView];
        blockSelf.notificationContentView = playerView;
      };
    } else {
      AVPlayerItem* firstPlayerItem = [self.assets firstObject];
      AVAssetTrack* track = [[firstPlayerItem.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
      CGSize trackSize = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
      float scaleRatio = self.view.frame.size.width / trackSize.width;
      scaledHeight = trackSize.height * scaleRatio;

      if (self.loopInitialContent) {
        AVQueuePlayer* videoPlayer = [AVQueuePlayer queuePlayerWithItems:@[ firstPlayerItem ]];
        self.videoPlayer = videoPlayer;
        self.playerLooper = [AVPlayerLooper playerLooperWithPlayer:videoPlayer
                                                      templateItem:firstPlayerItem];
      } else {
        self.videoPlayer = [AVPlayer playerWithPlayerItem:firstPlayerItem];
      }

      TeakAVPlayerView* playerView = [[TeakAVPlayerView alloc] init];
      playerView.player = self.videoPlayer;
      self.notificationContentView = playerView;

      __weak typeof(self) weakSelf = self;
      self.prepareContentView = ^{
        __strong typeof(self) blockSelf = weakSelf;
        [blockSelf createThumbnailViewForItem:blockSelf.videoPlayer.currentItem atTime:[blockSelf.videoPlayer currentTime]];
        [blockSelf.playerLooper disableLooping];
      };
    }

    /////

    self.notificationContentView.frame = CGRectMake(0, 0, self.view.frame.size.width, scaledHeight);

    self.view.frame = CGRectMake(self.view.frame.origin.x, self.view.frame.origin.y,
                                 self.view.frame.size.width, scaledHeight);
    self.preferredContentSize = CGSizeMake(self.view.frame.size.width, scaledHeight);
    [self.view addSubview:self.notificationContentView];

    // Start video if auto-play
    if (self.autoPlay) {
      [self.videoPlayer play];
    }
  }
}

- (void)didReceiveNotificationResponse:(UNNotificationResponse*)response
                     completionHandler:(void (^)(UNNotificationContentExtensionResponseOption))completionHandler {
  dispatch_once(&_inputHandlerDispatchOnce, ^{
    int attachmentIndex = (self.actions[response.actionIdentifier] == nil || self.actions[response.actionIdentifier] == [NSNull null]) ? -1 : [self.actions[response.actionIdentifier] intValue];

    if (attachmentIndex < 0) {
      // Launch the app when the button is pressed
      completionHandler(UNNotificationContentExtensionResponseOptionDismissAndForwardAction);
    } else {
      // Will prepare next content view
      self.prepareContentView();

      AVPlayerItem* assetToPlay = self.assets[attachmentIndex];
      AVPlayer* newPlayer = [AVPlayer playerWithPlayerItem:assetToPlay];
      [newPlayer play];
      TeakAVPlayerView* playerView = (TeakAVPlayerView*)self.notificationContentView;
      playerView.player = newPlayer;
      self.videoPlayer = newPlayer;
      // Start playing when button is pressed, launch app when the last asset finishes playing
      [[NSNotificationCenter defaultCenter] addObserverForName:AVPlayerItemDidPlayToEndTimeNotification
                                                        object:assetToPlay
                                                         queue:nil
                                                    usingBlock:^(NSNotification* notification) {
                                                      [[NSNotificationCenter defaultCenter] removeObserver:self];
                                                      completionHandler(UNNotificationContentExtensionResponseOptionDismissAndForwardAction);
                                                    }];
    }
  });
}

- (NSOperation*)sendMetricForPayload:(NSDictionary*)payload {
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://parsnip.gocarrot.com/notification_expanded"]];

  NSString* boundry = @"-===-httpB0unDarY-==-";

  NSMutableData* postData = [[NSMutableData alloc] init];

  for (NSString* key in payload) {
    [postData appendData:[[NSString stringWithFormat:@"--%@\r\n", boundry] dataUsingEncoding:NSUTF8StringEncoding]];
    [postData appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n%@\r\n", key, payload[key]] dataUsingEncoding:NSUTF8StringEncoding]];
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
