// Tests/tokenTickerTests/PKCEHelperTests.swift
import XCTest
@testable import token_ticker

final class PKCEHelperTests: XCTestCase {
    func testCodeVerifierLength() {
        let (verifier, _) = PKCEHelper.generatePair()
        // base64url of 32 bytes = 43 chars (no padding)
        XCTAssertEqual(verifier.count, 43)
    }

    func testCodeChallengeIsDeterministic() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        let challenge = PKCEHelper.challenge(for: verifier)
        // Known SHA-256 base64url of the above verifier (RFC 7636)
        XCTAssertEqual(challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        XCTAssertFalse(challenge.contains("+"))
        XCTAssertFalse(challenge.contains("/"))
        XCTAssertFalse(challenge.contains("="))
    }

    func testVerifierAndChallengeAreDifferent() {
        let (verifier, challenge) = PKCEHelper.generatePair()
        XCTAssertNotEqual(verifier, challenge)
    }
}
