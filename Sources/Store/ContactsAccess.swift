import Contacts
import Foundation

/// Wrapper around CNContactStore with AppleScript fallback for CLI usage.
/// CNContactStore requires TCC permission for the terminal app, which
/// unbundled CLI tools often cannot trigger. When denied, we fall back
/// to osascript JXA which routes through Contacts.app.
enum ContactsAccess {

    private static var useFallback: Bool = {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        switch status {
        case .authorized, .limited:
            return false
        case .notDetermined:
            // Try to get access; if it fails, use fallback
            let store = CNContactStore()
            let semaphore = DispatchSemaphore(value: 0)
            var granted = false
            store.requestAccess(for: .contacts) { result, _ in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            return !granted
        default:
            return true
        }
    }()

    /// Search contacts by name (given, family, or full name).
    static func search(name query: String) throws -> [ContactRecord] {
        if useFallback {
            fputs("(using Contacts.app fallback)\n", stderr)
            return try AppleScriptFallback.search(name: query)
        }
        let store = CNContactStore()
        let predicate = CNContact.predicateForContacts(matchingName: query)
        let contacts = try store.unifiedContacts(
            matching: predicate,
            keysToFetch: ContactRecord.fetchKeys
        )
        return contacts.map(ContactRecord.init)
    }

    /// Look up contacts by phone number.
    static func lookup(phone: String) throws -> [ContactRecord] {
        if useFallback {
            fputs("(using Contacts.app fallback)\n", stderr)
            return try AppleScriptFallback.lookup(phone: phone)
        }
        let store = CNContactStore()
        let phoneNumber = CNPhoneNumber(stringValue: phone)
        let predicate = CNContact.predicateForContacts(matching: phoneNumber)
        let contacts = try store.unifiedContacts(
            matching: predicate,
            keysToFetch: ContactRecord.fetchKeys
        )
        return contacts.map(ContactRecord.init)
    }

    /// Look up contacts by email address.
    static func lookup(email: String) throws -> [ContactRecord] {
        if useFallback {
            fputs("(using Contacts.app fallback)\n", stderr)
            return try AppleScriptFallback.lookup(email: email)
        }
        let store = CNContactStore()
        let predicate = CNContact.predicateForContacts(matchingEmailAddress: email)
        let contacts = try store.unifiedContacts(
            matching: predicate,
            keysToFetch: ContactRecord.fetchKeys
        )
        return contacts.map(ContactRecord.init)
    }

    /// Fetch a single contact by identifier.
    static func show(identifier: String) throws -> ContactRecord? {
        if useFallback {
            fputs("(using Contacts.app fallback)\n", stderr)
            return try AppleScriptFallback.show(identifier: identifier)
        }
        let store = CNContactStore()
        let predicate = CNContact.predicateForContacts(withIdentifiers: [identifier])
        let contacts = try store.unifiedContacts(
            matching: predicate,
            keysToFetch: ContactRecord.fetchKeys
        )
        return contacts.first.map(ContactRecord.init)
    }

    /// List all contacts, streamed via callback.
    static func listAll() throws -> [ContactRecord] {
        if useFallback {
            fputs("(using Contacts.app fallback)\n", stderr)
            return try AppleScriptFallback.listAll()
        }
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: ContactRecord.fetchKeys)
        request.sortOrder = .familyName
        var results: [ContactRecord] = []
        try store.enumerateContacts(with: request) { contact, _ in
            results.append(ContactRecord(from: contact))
        }
        return results
    }
}

enum ContactsError: Error, CustomStringConvertible {
    case denied
    case restricted

    var description: String {
        switch self {
        case .denied:
            return "Contacts access denied. Open System Settings > Privacy & Security > Contacts and enable access for your terminal app."
        case .restricted:
            return "Contacts access is restricted by a device management profile."
        }
    }
}
