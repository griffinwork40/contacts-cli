import Foundation

enum OutputFormat: String, CaseIterable, Sendable {
    case text
    case json
}

enum OutputFormatter {

    static func format(_ records: [ContactRecord], as fmt: OutputFormat) -> String {
        switch fmt {
        case .text:
            return formatText(records)
        case .json:
            return formatJSON(records)
        }
    }

    static func format(_ record: ContactRecord, as fmt: OutputFormat) -> String {
        format([record], as: fmt)
    }

    // MARK: - Text

    private static func formatText(_ records: [ContactRecord]) -> String {
        if records.isEmpty { return "No contacts found." }

        return records.map { record in
            var lines: [String] = []
            lines.append(record.fullName)

            if !record.nickname.isEmpty {
                lines.append("  aka \(record.nickname)")
            }
            if !record.organizationName.isEmpty, !record.givenName.isEmpty {
                lines.append("  org: \(record.organizationName)")
            }
            for phone in record.phoneNumbers {
                lines.append("  \(phone.label): \(phone.number)")
            }
            for email in record.emailAddresses {
                lines.append("  \(email.label): \(email.address)")
            }
            lines.append("  id: \(record.identifier)")
            return lines.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    // MARK: - JSON

    private static func formatJSON(_ records: [ContactRecord]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records),
              let json = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return json
    }
}
