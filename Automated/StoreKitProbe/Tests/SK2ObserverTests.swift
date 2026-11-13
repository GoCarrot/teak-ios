// Drives SK2 purchases (Swift, standing in for IAP 5 / a native SK2 game) and reads what the
// ObjC-only SK2Observer saw. Measurement: read the PROBE lines.
import XCTest
import StoreKit
import StoreKitTest
import SK2Observer

final class SK2ObserverTests: XCTestCase {
  var session: SKTestSession!

  override func setUpWithError() throws {
    let url = Bundle(for: SK2ObserverTests.self).url(forResource: "Probe", withExtension: "storekit")!
    session = try SKTestSession(contentsOf: url)
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    session.askToBuyEnabled = false
  }

  func testDumpStoreKitRuntime() {
    SK2Observer.dumpStoreKitRuntime()
  }

  // Red/green in one run: a consumable finished before the hook is installed must NOT be seen,
  // two finished after install must be, with ids matching what the purchaser got.
  func testFinishHookSeesConsumablesBeforeFinish() async throws {
    let p = try await Product.products(for: ["io.teak.probe.coins"]).first!
    var bought: [UInt64] = []
    func buyAndFinish(_ label: String) async throws {
      guard case .success(let v) = try await p.purchase(), case .verified(let t) = v else { return XCTFail("no verified purchase") }
      plog("finish-hook \(label): purchaser got tx id=\(t.id); finishing")
      bought.append(t.id)
      await t.finish()
    }
    try await buyAndFinish("pre-install")
    let rebound = SK2Observer.installFinishHook()
    plog("finish-hook: rebound slots=\(rebound)")
    try await buyAndFinish("post-install #1")
    try await buyAndFinish("post-install #2")
    let seen = SK2Observer.finishedIds().map { $0.uint64Value }
    plog("finish-hook RESULT iOS=\(UIDevice.current.systemVersion) bought=\(bought) hookSaw=\(seen) expected=\(Array(bought.dropFirst()))")
    let unfinished = await Transaction.unfinished.compactMap { r -> UInt64? in if case .verified(let t) = r { return t.id } else { return nil } }.collect()
    plog("finish-hook: Transaction.unfinished after=\(unfinished) (finish still reached StoreKit if empty)")
  }

  // IAP 5 reads verificationResult.jwsRepresentation for every purchase (PurchaseDetails.swift).
  // A read before install must not be seen; one after must, and match what the caller got.
  func testJWSHookSeesWhatTheCallerReads() async throws {
    let p = try await Product.products(for: ["io.teak.probe.coins"]).first!
    guard case .success(let v0) = try await p.purchase() else { return XCTFail("no purchase") }
    let pre = v0.jwsRepresentation
    let rebound = SK2Observer.installJWSHook()
    guard case .success(let v1) = try await p.purchase() else { return XCTFail("no purchase") }
    let post = v1.jwsRepresentation
    let seen = SK2Observer.seenJWS()
    plog("jws-hook RESULT iOS=\(UIDevice.current.systemVersion) rebound=\(rebound) seenCount=\(seen.count) matchesPost=\(seen.contains(post)) matchesPre=\(seen.contains(pre)) postLen=\(post.count)")
    if case .verified(let t) = v0 { await t.finish() }
    if case .verified(let t) = v1 { await t.finish() }
  }
}

extension AsyncSequence {
  func collect() async rethrows -> [Element] { var out: [Element] = []; for try await e in self { out.append(e) }; return out }
}
