import Contacts
import Foundation

/// Wrapper around CNContactStore for CLI usage.
enum ContactsAccess {

    /// Ensure we have contacts authorization; prompt if needed.
    static func ensureAuthorized() throws {
        let store = CNContactStore()
        let status = CNContactStore.authorizationStatus(for: .contacts)

        switch status {
        case .authorized:
            return
        case .notDetermined:
            if !requestAccessSync(store: store) {
                throw ContactsError.denied
            }
        case .denied:
            throw ContactsError.denied
        case .restricted:
            throw ContactsError.restricted
        case .limited:
            fputs("Warning: limited contacts access -- results may be incomplete.\n", stderr)
        @unknown default:
            throw ContactsError.denied
        }
    }

    /// Search contacts by name (given, family, or full name).
    static func search(name query: String) throws -> [ContactRecord] {
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
        let store = CNContactStore()
        let request = CNContactFetchRequest(keysToFetch: ContactRecord.fetchKeys)
        request.sortOrder = .familyName
        var results: [ContactRecord] = []
        try store.enumerateContacts(with: request) { contact, _ in
            results.append(ContactRecord(from: contact))
        }
        return results
    }

    // MARK: - Private

    private static func requestAccessSync(store: CNContactStore) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var granted = false
        store.requestAccess(for: .contacts) { result, _ in
            granted = result
            semaphore.signal()
        }
        semaphore.wait()
        return granted
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
