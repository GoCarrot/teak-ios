// Probe: which StoreKit purchases reach Teak's SKPaymentObserver (SK1 queue).
// Teak.framework is real; +[PurchaseEvent purchaseSucceeded:] is swizzled to count calls.
// Measurement, not assertions: read the PROBE lines (see README).
import XCTest
import StoreKit
import StoreKitTest
import ObjectiveC
import Teak

let logPath = ProcessInfo.processInfo.environment["PROBE_LOG"] ?? "/tmp/storekit-probe.log"
func plog(_ s: String) {
  let line = "PROBE " + s + "\n"
  NSLog("%@", line)
  if let h = FileHandle(forWritingAtPath: logPath) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile() }
  else { FileManager.default.createFile(atPath: logPath, contents: line.data(using: .utf8)) }
}

final class ProbeTests: XCTestCase {
  static let lock = NSLock()
  static var succeeded: [[String: Any]] = []
  static var updates: [UInt64] = []
  static var swizzled = false
  var session: SKTestSession!
  var observer: SKPaymentTransactionObserver!

  override class func setUp() {
    guard !swizzled else { return }
    swizzled = true
    let cls: AnyClass = NSClassFromString("PurchaseEvent")!
    let m = class_getClassMethod(cls, NSSelectorFromString("purchaseSucceeded:"))!
    let blk: @convention(block) (AnyObject, NSDictionary) -> Void = { _, p in
      lock.lock(); succeeded.append(p as! [String: Any]); lock.unlock()
    }
    method_setImplementation(m, imp_implementationWithBlock(blk))
    plog("swizzled PurchaseEvent.purchaseSucceeded:")
  }

  override func setUpWithError() throws {
    ProbeTests.succeeded = []
    ProbeTests.updates = []
    let url = Bundle(for: ProbeTests.self).url(forResource: "Probe", withExtension: "storekit")!
    session = try SKTestSession(contentsOf: url)
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    session.askToBuyEnabled = false
    let obsClass = NSClassFromString("SKPaymentObserver") as! NSObject.Type
    observer = (obsClass.init() as AnyObject) as? SKPaymentTransactionObserver
    XCTAssertNotNil(observer, "SKPaymentObserver should conform to SKPaymentTransactionObserver")
    SKPaymentQueue.default().add(observer)
  }

  override func tearDown() {
    SKPaymentQueue.default().remove(observer)
  }

  func report(_ name: String) {
    ProbeTests.lock.lock(); let s = ProbeTests.succeeded; ProbeTests.lock.unlock()
    let ids = s.map { "\($0["transaction_identifier"] ?? "nil")" }
    plog("\(name): updatesDelivered=\(ProbeTests.updates) iOS=\(UIDevice.current.systemVersion) teakPurchaseSucceededCalls=\(s.count) txIds=\(ids) keys=\(s.first.map { Array($0.keys).sorted() } ?? [])")
  }

  // Passive-read check: does the on-device app receipt (what Teak sends as purchase_token)
  // gain an in_app entry per purchase? Counts raw occurrences of the product id string, so
  // no ASN.1 parsing. Two purchases per path so growth is visible. Run each receipt test
  // alone on an erased simulator: the receipt file persists across tests.
  func receiptInfo() -> String {
    guard let url = Bundle.main.appStoreReceiptURL else { return "receiptURL=nil" }
    guard let data = try? Data(contentsOf: url) else { return "receipt=missing(\(url.lastPathComponent))" }
    let n = Array("io.teak.probe.coins".utf8); let b = [UInt8](data); var c = 0
    if b.count >= n.count { for i in 0...(b.count - n.count) where b[i] == n[0] && Array(b[i..<(i + n.count)]) == n { c += 1 } }
    return "receiptBytes=\(data.count) productIdOccurrences=\(c)"
  }

  func testReceiptAfterSK2Purchases() async throws {
    plog("SK2 receipt before: \(receiptInfo())")
    let p = try await Product.products(for: ["io.teak.probe.coins"]).first!
    for i in 1...2 {
      guard case .success(let v) = try await p.purchase(), case .verified(let t) = v else { return XCTFail("no verified purchase") }
      plog("SK2 purchase #\(i) tx id=\(t.id); receipt immediately: \(receiptInfo())")
      try await Task.sleep(nanoseconds: 4_000_000_000)
      plog("SK2 purchase #\(i) receipt 4s later: \(receiptInfo())")
      await t.finish()
      try await Task.sleep(nanoseconds: 4_000_000_000)
      plog("SK2 purchase #\(i) receipt 4s after finish: \(receiptInfo())")
    }
  }

  func testReceiptAfterSK1Purchases() async throws {
    plog("SK1 receipt before: \(receiptInfo())")
    for i in 1...2 {
      let pay = SKMutablePayment(); pay.productIdentifier = "io.teak.probe.coins"
      SKPaymentQueue.default().add(pay)
      try await Task.sleep(nanoseconds: 5_000_000_000)
      plog("SK1 purchase #\(i); receipt: \(receiptInfo())")
    }
  }

  func testSK1Control() async throws {
    // SKProductsRequest reports the config product invalid under SKTestSession, so buy by identifier.
    let pay = SKMutablePayment(); pay.productIdentifier = "io.teak.probe.coins"
    SKPaymentQueue.default().add(pay)
    try await Task.sleep(nanoseconds: 8_000_000_000)
    report("SK1-control (SKPaymentQueue.add)")
  }

  func testSK2PurchaseNoFinish() async throws {
    let p = try await Product.products(for: ["io.teak.probe.coins"]).first!
    let r = try await p.purchase()
    if case .success(let v) = r, case .verified(let t) = v { plog("SK2 purchase returned verified tx id=\(t.id) (not finished)") }
    else { plog("SK2 purchase result: \(r)") }
    try await Task.sleep(nanoseconds: 8_000_000_000)
    report("SK2-purchase-no-finish")
  }

  func testSK2PurchaseThenObserverAttachedLate() async throws {
    SKPaymentQueue.default().remove(observer)
    let p = try await Product.products(for: ["io.teak.probe.coins"]).first!
    let r = try await p.purchase()
    if case .success(let v) = r, case .verified(let t) = v { plog("SK2 purchase returned verified tx id=\(t.id) (not finished); attaching SK1 observer now") }
    SKPaymentQueue.default().add(observer)
    try await Task.sleep(nanoseconds: 8_000_000_000)
    report("SK2-purchase-then-observer-attached-late")
  }

  // Positive control for the Transaction.updates result: the listener must emit
  // an unfinished transaction that predates it, or "nothing delivered" proves nothing.
  func testUpdatesListenerSeesUnfinishedTransactionOnStart() async throws {
    let p = try await Product.products(for: ["io.teak.probe.coins"]).first!
    let r = try await p.purchase()
    if case .success(let v) = r, case .verified(let t) = v { plog("SK2 purchase returned verified tx id=\(t.id) (not finished); starting updates listener now") }
    let listener = Task { for await u in Transaction.updates { if case .verified(let t) = u { plog("Transaction.updates delivered tx id=\(t.id)"); ProbeTests.lock.lock(); ProbeTests.updates.append(t.id); ProbeTests.lock.unlock() } } }
    defer { listener.cancel() }
    try await Task.sleep(nanoseconds: 8_000_000_000)
    report("updates-listener-positive-control")
  }

  func testSK2PurchaseWithUpdatesListenerAndFinish() async throws {
    // Mimics Unity IAP 5: Transaction.updates listener running, finish on confirm.
    let listener = Task { for await u in Transaction.updates { if case .verified(let t) = u { plog("Transaction.updates delivered tx id=\(t.id)"); ProbeTests.lock.lock(); ProbeTests.updates.append(t.id); ProbeTests.lock.unlock() } } }
    defer { listener.cancel() }
    let p = try await Product.products(for: ["io.teak.probe.coins"]).first!
    let r = try await p.purchase()
    if case .success(let v) = r, case .verified(let t) = v { plog("SK2 purchase returned verified tx id=\(t.id); finishing"); await t.finish() }
    try await Task.sleep(nanoseconds: 8_000_000_000)
    report("SK2-purchase-with-updates-listener-and-finish")
  }
}

final class ProductsFetcher: NSObject, SKProductsRequestDelegate {
  var cont: CheckedContinuation<SKProduct, Error>?
  var req: SKProductsRequest?
  func fetch(_ id: String) async throws -> SKProduct {
    try await withCheckedThrowingContinuation { c in
      cont = c; req = SKProductsRequest(productIdentifiers: [id]); req!.delegate = self; req!.start()
    }
  }
  func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
    plog("SKProductsResponse products=\(response.products.map { $0.productIdentifier }) invalid=\(response.invalidProductIdentifiers)")
    if let p = response.products.first { cont?.resume(returning: p) } else { cont?.resume(throwing: NSError(domain: "probe", code: 1)) }
  }
  func request(_ request: SKRequest, didFailWithError error: Error) { cont?.resume(throwing: error) }
}
