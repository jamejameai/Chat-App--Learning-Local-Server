import XCTest
import CryptoKit
@testable import MiniTelegram

final class SenderKeysTests: XCTestCase {

    func testGroupSenderKeyDistributionAndDecryption() throws {
        // 1. Alice creates outbound sender key for Group 1
        let aliceOutbound = SenderKeySession(
            groupId: "group-101",
            senderUserId: "alice-id",
            senderDeviceId: "alice-dev-1"
        )

        // 2. Alice generates distribution message
        let distributionMsg = aliceOutbound.createDistributionMessage()

        // 3. Bob and Charlie receive distribution message
        let bobInbound = try SenderKeySession(distribution: distributionMsg)
        let charlieInbound = try SenderKeySession(distribution: distributionMsg)

        // 4. Alice sends group message 1
        let text1 = "Welcome team to the encrypted channel!"
        let env1 = try aliceOutbound.encrypt(plaintext: Data(text1.utf8))

        // Both Bob and Charlie decrypt
        let bobDecrypted1 = try bobInbound.decrypt(envelope: env1)
        let charlieDecrypted1 = try charlieInbound.decrypt(envelope: env1)

        XCTAssertEqual(String(data: bobDecrypted1, encoding: .utf8), text1)
        XCTAssertEqual(String(data: charlieDecrypted1, encoding: .utf8), text1)

        // 5. Alice sends group message 2
        let text2 = "Here is our confidential plan update."
        let env2 = try aliceOutbound.encrypt(plaintext: Data(text2.utf8))

        let bobDecrypted2 = try bobInbound.decrypt(envelope: env2)
        let charlieDecrypted2 = try charlieInbound.decrypt(envelope: env2)

        XCTAssertEqual(String(data: bobDecrypted2, encoding: .utf8), text2)
        XCTAssertEqual(String(data: charlieDecrypted2, encoding: .utf8), text2)
    }

    func testGroupRekeyingExcludesRemovedMember() throws {
        // Alice creates initial session
        let aliceOutboundEpoch1 = SenderKeySession(
            groupId: "group-101",
            senderUserId: "alice-id",
            senderDeviceId: "alice-dev-1"
        )
        let distEpoch1 = aliceOutboundEpoch1.createDistributionMessage()

        // Bob and Eve receive Epoch 1 keys
        let bobInbound = try SenderKeySession(distribution: distEpoch1)
        let eveInbound = try SenderKeySession(distribution: distEpoch1)

        // Eve can read Epoch 1 messages
        let msg1 = try aliceOutboundEpoch1.encrypt(plaintext: Data("Epoch 1 message".utf8))
        XCTAssertEqual(String(data: try eveInbound.decrypt(envelope: msg1), encoding: .utf8), "Epoch 1 message")
        XCTAssertEqual(String(data: try bobInbound.decrypt(envelope: msg1), encoding: .utf8), "Epoch 1 message")

        // Member Eve is removed! Group rekeys: Alice generates fresh Epoch 2 session
        let aliceOutboundEpoch2 = SenderKeySession(
            groupId: "group-101",
            senderUserId: "alice-id",
            senderDeviceId: "alice-dev-1"
        )
        let distEpoch2 = aliceOutboundEpoch2.createDistributionMessage()

        // Distribute Epoch 2 keys only to Bob (Eve is excluded)
        let bobInboundEpoch2 = try SenderKeySession(distribution: distEpoch2)

        // Alice sends Epoch 2 message
        let msg2 = try aliceOutboundEpoch2.encrypt(plaintext: Data("Confidential after Eve removed".utf8))

        // Bob decrypts successfully
        let bobDecrypted = try bobInboundEpoch2.decrypt(envelope: msg2)
        XCTAssertEqual(String(data: bobDecrypted, encoding: .utf8), "Confidential after Eve removed")

        // Eve attempts to decrypt with her outdated keys -> Must fail!
        XCTAssertThrowsError(try eveInbound.decrypt(envelope: msg2))
    }
}
