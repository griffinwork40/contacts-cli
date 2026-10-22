import Foundation

/// Fallback contact access via osascript (JXA) when CNContactStore TCC is denied.
/// Routes through Contacts.app which has its own system-level access.
enum AppleScriptFallback {

    /// Search contacts by name.
    static func search(name query: String) throws -> [ContactRecord] {
        let escaped = query.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        const app = Application('Contacts');
        const people = app.people.whose({name: {_contains: '\(escaped)'}});
        const results = [];
        for (let i = 0; i < people.length; i++) {
            const p = people[i];
            const phones = [];
            try {
                for (let j = 0; j < p.phones.length; j++) {
                    phones.push({label: p.phones[j].label() || 'other', number: p.phones[j].value()});
                }
            } catch(e) {}
            const emails = [];
            try {
                for (let j = 0; j < p.emails.length; j++) {
                    emails.push({label: p.emails[j].label() || 'other', address: p.emails[j].value()});
                }
            } catch(e) {}
            results.push({
                identifier: p.id(),
                givenName: p.firstName() || '',
                familyName: p.lastName() || '',
                organizationName: p.organization() || '',
                nickname: p.nickname() || '',
                phoneNumbers: phones,
                emailAddresses: emails
            });
        }
        JSON.stringify(results);
        """
        return try runJXA(script)
    }

    /// Look up contacts by phone number (substring match).
    static func lookup(phone: String) throws -> [ContactRecord] {
        let escaped = phone.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        const app = Application('Contacts');
        const people = app.people();
        const results = [];
        const target = '\(escaped)'.replace(/[^0-9+]/g, '');
        for (let i = 0; i < people.length; i++) {
            const p = people[i];
            let matched = false;
            const phones = [];
            try {
                for (let j = 0; j < p.phones.length; j++) {
                    const num = p.phones[j].value();
                    phones.push({label: p.phones[j].label() || 'other', number: num});
                    if (num.replace(/[^0-9+]/g, '').includes(target)) matched = true;
                }
            } catch(e) {}
            if (!matched) continue;
            const emails = [];
            try {
                for (let j = 0; j < p.emails.length; j++) {
                    emails.push({label: p.emails[j].label() || 'other', address: p.emails[j].value()});
                }
            } catch(e) {}
            results.push({
                identifier: p.id(),
                givenName: p.firstName() || '',
                familyName: p.lastName() || '',
                organizationName: p.organization() || '',
                nickname: p.nickname() || '',
                phoneNumbers: phones,
                emailAddresses: emails
            });
        }
        JSON.stringify(results);
        """
        return try runJXA(script)
    }

    /// Look up contacts by email address.
    static func lookup(email: String) throws -> [ContactRecord] {
        let escaped = email.lowercased().replacingOccurrences(of: "'", with: "\\'")
        let script = """
        const app = Application('Contacts');
        const people = app.people();
        const results = [];
        const target = '\(escaped)';
        for (let i = 0; i < people.length; i++) {
            const p = people[i];
            let matched = false;
            const emails = [];
            try {
                for (let j = 0; j < p.emails.length; j++) {
                    const addr = p.emails[j].value();
                    emails.push({label: p.emails[j].label() || 'other', address: addr});
                    if (addr.toLowerCase() === target) matched = true;
                }
            } catch(e) {}
            if (!matched) continue;
            const phones = [];
            try {
                for (let j = 0; j < p.phones.length; j++) {
                    phones.push({label: p.phones[j].label() || 'other', number: p.phones[j].value()});
                }
            } catch(e) {}
            results.push({
                identifier: p.id(),
                givenName: p.firstName() || '',
                familyName: p.lastName() || '',
                organizationName: p.organization() || '',
                nickname: p.nickname() || '',
                phoneNumbers: phones,
                emailAddresses: emails
            });
        }
        JSON.stringify(results);
        """
        return try runJXA(script)
    }

    /// Show a single contact by identifier.
    static func show(identifier: String) throws -> ContactRecord? {
        let escaped = identifier.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        const app = Application('Contacts');
        let p;
        try { p = app.people.byId('\(escaped)'); p.id(); } catch(e) { '[]'; }
        const phones = [];
        try {
            for (let j = 0; j < p.phones.length; j++) {
                phones.push({label: p.phones[j].label() || 'other', number: p.phones[j].value()});
            }
        } catch(e) {}
        const emails = [];
        try {
            for (let j = 0; j < p.emails.length; j++) {
                emails.push({label: p.emails[j].label() || 'other', address: p.emails[j].value()});
            }
        } catch(e) {}
        JSON.stringify([{
            identifier: p.id(),
            givenName: p.firstName() || '',
            familyName: p.lastName() || '',
            organizationName: p.organization() || '',
            nickname: p.nickname() || '',
            phoneNumbers: phones,
            emailAddresses: emails
        }]);
        """
        let results: [ContactRecord] = try runJXA(script)
        return results.first
    }

    /// List all contacts.
    static func listAll() throws -> [ContactRecord] {
        let script = """
        const app = Application('Contacts');
        const people = app.people();
        const results = [];
        for (let i = 0; i < people.length; i++) {
            const p = people[i];
            const phones = [];
            try {
                for (let j = 0; j < p.phones.length; j++) {
                    phones.push({label: p.phones[j].label() || 'other', number: p.phones[j].value()});
                }
            } catch(e) {}
            const emails = [];
            try {
                for (let j = 0; j < p.emails.length; j++) {
                    emails.push({label: p.emails[j].label() || 'other', address: p.emails[j].value()});
                }
            } catch(e) {}
            results.push({
                identifier: p.id(),
                givenName: p.firstName() || '',
                familyName: p.lastName() || '',
                organizationName: p.organization() || '',
                nickname: p.nickname() || '',
                phoneNumbers: phones,
                emailAddresses: emails
            });
        }
        JSON.stringify(results);
        """
        return try runJXA(script)
    }

    // MARK: - Private

    private static func runJXA(_ script: String) throws -> [ContactRecord] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", script]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errData = stderr.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? "Unknown error"
            throw AppleScriptError.executionFailed(errStr.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        guard !data.isEmpty else { return [] }

        // osascript wraps output in quotes and escapes; clean it
        var jsonString = String(data: data, encoding: .utf8) ?? "[]"
        jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)

        // osascript -l JavaScript returns the last expression as a string literal
        // with surrounding quotes — strip them if present
        if jsonString.hasPrefix("\"") && jsonString.hasSuffix("\"") {
            jsonString = String(jsonString.dropFirst().dropLast())
            jsonString = jsonString.replacingOccurrences(of: "\\\"", with: "\"")
            jsonString = jsonString.replacingOccurrences(of: "\\n", with: "\n")
            jsonString = jsonString.replacingOccurrences(of: "\\\\", with: "\\")
        }

        guard let jsonData = jsonString.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ContactRecord].self, from: jsonData)) ?? []
    }
}

enum AppleScriptError: Error, CustomStringConvertible {
    case executionFailed(String)

    var description: String {
        switch self {
        case .executionFailed(let msg):
            return "AppleScript fallback failed: \(msg)"
        }
    }
}
