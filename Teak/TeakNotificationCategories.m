#import "Teak+Internal.h"

NSDictionary* TeakNotificationCategories = nil;
NSBundle* TeakResourceBundle = nil;

NSString* TeakLocalizedStringWithDefaultValue(NSString* key, NSString* tbl, NSBundle* bundle, NSString* val, NSString* comment) {
  NSString* ret = NSLocalizedStringWithDefaultValue(key, tbl, bundle, val, comment);
  return [ret length] > 0 ? ret : val;
}

__attribute__((constructor)) void teak_init_notification_categories(void) {
  @try {
    NSURL* bundleUrl = [[NSBundle mainBundle] URLForResource:@"TeakResources" withExtension:@"bundle"];
    TeakResourceBundle = [NSBundle bundleWithURL:bundleUrl];
  } @catch (NSException* ignored) {
    NSLog(@"Teak: Resources bundle not present. Only English localization supported.");
    TeakResourceBundle = nil;
  }

  // TODO: Need CSV to handle the localization notes (comment)
  TeakNotificationCategories = @{
    @"TeakNotificationPlayNow" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"play_now",
          TeakLocalizedStringWithDefaultValue(@"play_now", nil, TeakResourceBundle, @"Play Now",
                                              @"Play Now")
        ],
      ]
    },
  
    @"TeakNotificationClaimForFree" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"claim_for_free",
          TeakLocalizedStringWithDefaultValue(@"claim_for_free", nil, TeakResourceBundle, @"CLAIM FOR FREE",
                                              @"CLAIM FOR FREE")
        ],
      ]
    },
  
    @"TeakNotificationBox123" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"box_1",
          TeakLocalizedStringWithDefaultValue(@"box_1", nil, TeakResourceBundle, @"Box 1",
                                              @"Box 1")
        ],@[
          @"box_2",
          TeakLocalizedStringWithDefaultValue(@"box_2", nil, TeakResourceBundle, @"Box 2",
                                              @"Box 2")
        ],@[
          @"box_3",
          TeakLocalizedStringWithDefaultValue(@"box_3", nil, TeakResourceBundle, @"Box 3",
                                              @"Box 3")
        ],
      ]
    },
  
    @"TeakNotificationGetNow" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"get_now",
          TeakLocalizedStringWithDefaultValue(@"get_now", nil, TeakResourceBundle, @"GET NOW",
                                              @"GET NOW")
        ],
      ]
    },
  
    @"TeakNotificationBuyNow" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"buy_now",
          TeakLocalizedStringWithDefaultValue(@"buy_now", nil, TeakResourceBundle, @"BUY NOW",
                                              @"BUY NOW")
        ],
      ]
    },
  
    @"TeakNotificationInteractiveStop" : @{
      @"interactive" : @YES,
      @"actions" : @[
        @[
          @"stop",
          TeakLocalizedStringWithDefaultValue(@"stop", nil, TeakResourceBundle, @"STOP",
                                              @"STOP")
        ],
      ]
    },
  
    @"TeakNotificationLaughingEmoji" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @":smile:",
          TeakLocalizedStringWithDefaultValue(@":smile:", nil, TeakResourceBundle, @"😄",
                                              @"😄")
        ],
      ]
    },
  
    @"TeakNotificationThumbsUpEmoji" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @":thumbsup:",
          TeakLocalizedStringWithDefaultValue(@":thumbsup:", nil, TeakResourceBundle, @"👍",
                                              @"👍")
        ],
      ]
    },
  
    @"TeakNotificationPartyEmoji" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @":tada:",
          TeakLocalizedStringWithDefaultValue(@":tada:", nil, TeakResourceBundle, @"🎉",
                                              @"🎉")
        ],
      ]
    },
  
    @"TeakNotificationSlotEmoji" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @":slot_machine:",
          TeakLocalizedStringWithDefaultValue(@":slot_machine:", nil, TeakResourceBundle, @"🎰",
                                              @"🎰")
        ],
      ]
    },
  
    @"TeakNotification123" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @":one:",
          TeakLocalizedStringWithDefaultValue(@":one:", nil, TeakResourceBundle, @"1️⃣",
                                              @"1️⃣")
        ],@[
          @":two:",
          TeakLocalizedStringWithDefaultValue(@":two:", nil, TeakResourceBundle, @"2️⃣",
                                              @"2️⃣")
        ],@[
          @":three:",
          TeakLocalizedStringWithDefaultValue(@":three:", nil, TeakResourceBundle, @"3️⃣",
                                              @"3️⃣")
        ],
      ]
    },
  
    @"TeakNotificationFreeGiftEmoji" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"get_my_free_:gift:",
          TeakLocalizedStringWithDefaultValue(@"get_my_free_:gift:", nil, TeakResourceBundle, @"GET MY FREE 🎁",
                                              @"GET MY FREE 🎁")
        ],
      ]
    },
  
    @"TeakNotificationYes" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"yes",
          TeakLocalizedStringWithDefaultValue(@"yes", nil, TeakResourceBundle, @"Yes",
                                              @"Yes")
        ],
      ]
    },
  
    @"TeakNotificationYesNo" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"yes",
          TeakLocalizedStringWithDefaultValue(@"yes", nil, TeakResourceBundle, @"Yes",
                                              @"Yes")
        ],@[
          @"no",
          TeakLocalizedStringWithDefaultValue(@"no", nil, TeakResourceBundle, @"No",
                                              @"No")
        ],
      ]
    },
  
    @"TeakNotificationAccept" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"accept",
          TeakLocalizedStringWithDefaultValue(@"accept", nil, TeakResourceBundle, @"Accept",
                                              @"Accept")
        ],
      ]
    },
  
    @"TeakNotificationOkay" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"okay",
          TeakLocalizedStringWithDefaultValue(@"okay", nil, TeakResourceBundle, @"Okay",
                                              @"Okay")
        ],
      ]
    },
  
    @"TeakNotificationYesPlease" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"yes,_please",
          TeakLocalizedStringWithDefaultValue(@"yes,_please", nil, TeakResourceBundle, @"Yes, please",
                                              @"Yes, please")
        ],
      ]
    },
  
    @"TeakNotificationClaimFreeBonus" : @{
      @"interactive" : @NO,
      @"actions" : @[
        @[
          @"claim_free_bonus",
          TeakLocalizedStringWithDefaultValue(@"claim_free_bonus", nil, TeakResourceBundle, @"Claim Free Bonus",
                                              @"Claim Free Bonus")
        ],
      ]
    },
  };
}
