//
//  LenientDecodeTests.swift
//  BuddyAppKitTests
//
//  Coverage for the forgiving, logged `lenientDecodeIfPresent` (#646): a missing key,
//  explicit null, or type mismatch all yield `nil` instead of throwing, while a present,
//  well-typed value decodes normally.
//

import BuddyAppKit
import Foundation
import Testing

@Suite("Lenient decode")
struct LenientDecodeTests {
    /// A model that decodes every field leniently, so one bad field defaults to `nil`
    /// rather than failing the whole decode.
    private struct Model: Decodable {
        let name: String?
        let count: Int?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = container.lenientDecodeIfPresent(String.self, forKey: .name)
            count = container.lenientDecodeIfPresent(Int.self, forKey: .count)
        }

        enum CodingKeys: String, CodingKey {
            case name
            case count
        }
    }

    private func decode(_ json: String) throws -> Model {
        try JSONDecoder().decode(Model.self, from: Data(json.utf8))
    }

    @Test
    func `present well-typed values decode normally`() throws {
        let model = try decode(#"{"name": "Polly", "count": 3}"#)
        #expect(model.name == "Polly")
        #expect(model.count == 3)
    }

    @Test
    func `a missing key yields nil`() throws {
        let model = try decode(#"{"name": "Polly"}"#)
        #expect(model.name == "Polly")
        #expect(model.count == nil)
    }

    @Test
    func `an explicit null yields nil`() throws {
        let model = try decode(#"{"name": null, "count": 3}"#)
        #expect(model.name == nil)
        #expect(model.count == 3)
    }

    @Test
    func `a type mismatch yields nil instead of throwing`() throws {
        // `count` is a string here; a strict decode would throw and lose the whole record.
        let model = try decode(#"{"name": "Polly", "count": "lots"}"#)
        #expect(model.name == "Polly")
        #expect(model.count == nil)
    }
}
