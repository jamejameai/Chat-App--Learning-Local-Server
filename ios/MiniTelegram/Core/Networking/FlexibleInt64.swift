import Foundation

/// A 64-bit integer that decodes from either a JSON number or a numeric string.
///
/// The server returns Postgres BIGINT values (e.g. message sequence ids) as strings, so a plain
/// `Int64` field fails to decode with "isn't in the correct format".
public struct FlexibleInt64: Codable, Equatable, Sendable {
    public let value: Int64

    public init(_ value: Int64) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) {
            value = number
            return
        }
        let text = try container.decode(String.self)
        guard let parsed = Int64(text.trimmingCharacters(in: .whitespaces)) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an integer or numeric string, got \"\(text)\""
            )
        }
        value = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
