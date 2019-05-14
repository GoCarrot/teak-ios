/* Teak Example -- Copyright (C) 2016 GoCarrot Inc.
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

#import "ViewController.h"
#import "User.h"
#import <Teak/Teak.h>

extern void TeakReportTestException(void);

@import StoreKit;

@interface ViewController () <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@end

@implementation ViewController {
  User* user;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
  [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
  user = [User user];
}

- (void)didReceiveMemoryWarning {
  [super didReceiveMemoryWarning];
  // Dispose of any resources that can be recreated.
}

- (IBAction)makePurchase {
  //
  SKProductsRequest* productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:@[ @"io.teak.demo.angrybots.dollar" ]]];

  productsRequest.delegate = self;
  [productsRequest start];
}

- (IBAction)playPonies {
  NSString* slot = @"OMG Ponies🐴";
  SlotWin winInfo = [user playSlot:slot];

  UIAlertController* alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Played '%@'", slot]
                                                                 message:[NSString stringWithFormat:@"You bet %u coins and won %u! Now you have %u.", (unsigned long)winInfo.wager, (unsigned long)winInfo.win, (unsigned long)user.coins]
                                                          preferredStyle:UIAlertControllerStyleAlert];

  __block ViewController* blockSelf = self;

  UIAlertAction* spinAgain = [UIAlertAction actionWithTitle:@"Spin Again"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction* action){ [blockSelf playPonies]; }];

  UIAlertAction* backToLobby = [UIAlertAction actionWithTitle:@"Back to Lobby"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction* action){}];

  [alert addAction:spinAgain];
  [alert addAction:backToLobby];

  [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:alert animated:NO completion:nil];
}

- (IBAction)crashApp {
  NSArray *slots = [NSArray arrayWithObjects:
                    @"OMG Ponies🐴",
                    @"🦄Unicorn Gold🦄",
                    @"Golden 🐷 Festival",
                    @"パチンコ",
                    @"🌶️🌶️Spicy Slots🌶️🌶️",
                    nil
                    ];
  NSString *slot = [slots objectAtIndex:arc4random_uniform([slots count])];
  uint32_t coins = arc4random_uniform(2000000000);
  
  /*[[Teak sharedInstance] trackEventWithActionId:@"test0" forObjectTypeId:nil andObjectInstanceId:nil];
  [[Teak sharedInstance] trackEventWithActionId:@"test1" forObjectTypeId:nil andObjectInstanceId:nil];
  [[Teak sharedInstance] trackEventWithActionId:@"test2" forObjectTypeId:nil andObjectInstanceId:nil];*/

  [[Teak sharedInstance] setNumericAttribute:coins forKey:@"coins"];
  [[Teak sharedInstance] setStringAttribute:slot forKey:@"last_slot"];
  [[Teak sharedInstance] trackEventWithActionId:@"foo" forObjectTypeId:@"bar" andObjectInstanceId:@"baz"];
  [[Teak sharedInstance] trackEventWithActionId:@"also" forObjectTypeId:@"this" andObjectInstanceId:@"thing"];
  
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Played Game!"
                                                                 message:[NSString stringWithFormat:@"You played '%@' and now have %u coins!", slot, coins]
                                                          preferredStyle:UIAlertControllerStyleAlert];
  
  UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"Awesome"
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction* action){}];
  
  [alert addAction:defaultAction];
  [[[[UIApplication sharedApplication] keyWindow] rootViewController] presentViewController:alert animated:YES completion:nil];

  //TeakReportTestException();
  return;

  //raise (SIGABRT);
  //return;
  NSString* bar = nil;
  NSDictionary* foo = @{
    @"foo" : bar
  };
  NSLog(@"%@", foo);
}

- (void)productsRequest:(SKProductsRequest*)request didReceiveResponse:(SKProductsResponse*)response {
  if (response.products.count > 0) {
    SKProduct* product = [response.products objectAtIndex:0];
    NSLocale* priceLocale = product.priceLocale;
    NSString* currencyCode = [priceLocale objectForKey:NSLocaleCurrencyCode];
    NSDecimalNumber* price = product.price;
    NSLog(@"Purchase info: %@ - %@ - %@", product.productIdentifier, currencyCode, price);

    SKMutablePayment* payment = [SKMutablePayment paymentWithProduct:product];
    payment.quantity = 1;
    [[SKPaymentQueue defaultQueue] addPayment:payment];
  }
}

- (void)paymentQueue:(SKPaymentQueue*)queue updatedTransactions:(NSArray<SKPaymentTransaction*>*)transactions {
  for (SKPaymentTransaction* transaction in transactions) {
    if (transaction.transactionState == SKPaymentTransactionStatePurchased ||
        transaction.transactionState == SKPaymentTransactionStateFailed) {
      [queue finishTransaction:transaction];
    }
  }
}

- (IBAction)scheduleNotification:(id)sender {
  TeakNotification* notif = [TeakNotification scheduleNotificationForCreative:@"test_deeplink" withMessage:@"Test notif" secondsFromNow:10];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    while (notif.completed == NO) {
      sleep(1);
    }
    NSLog(@"Notification scheduled: %@", notif.teakNotifId);
  });
}

@end
