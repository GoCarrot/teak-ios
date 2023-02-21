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
#import <Teak/Teak.h>

extern void TeakReportTestException(void);

@import StoreKit;

@interface ViewController () <SKPaymentTransactionObserver, SKProductsRequestDelegate>

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  // Do any additional setup after loading the view, typically from a nib.
  [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
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

- (IBAction)crashApp {
  /*[[Teak sharedInstance] trackEventWithActionId:@"test0" forObjectTypeId:nil andObjectInstanceId:nil];
  [[Teak sharedInstance] trackEventWithActionId:@"test1" forObjectTypeId:nil andObjectInstanceId:nil];
  [[Teak sharedInstance] trackEventWithActionId:@"test2" forObjectTypeId:nil andObjectInstanceId:nil];*/
  //[[Teak sharedInstance] setNumericAttribute:(drand48() * DBL_MAX) forKey:@"coins"];
//  [[Teak sharedInstance] setStringAttribute:@"asshole_cats" forKey:@"last_slot"];
//  [[Teak sharedInstance] incrementEventWithActionId:@"spin" forObjectTypeId:@"slot" andObjectInstanceId:@"asshole_cats" count:1];
//  [[Teak sharedInstance] incrementEventWithActionId:@"coin_sink" forObjectTypeId:@"slot" andObjectInstanceId:@"asshole_cats" count:50000];
  [[Teak sharedInstance] setState:TeakChannelStateAvailable forChannel:TeakChannelTypePlatformPush];
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
