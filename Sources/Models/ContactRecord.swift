import Contacts
import Foundation

/// A lightweight, Codable representation of a CNContact for CLI output.
struct ContactRecord: Codable, Sendable {
    let identifier: String
    let givenName: String
    let familyName: String
    let organizationName: String
    let nickname: String
    let phoneNumbers: [LabeledPhone]
    let emailAddresses: [LabeledEmail]

    struct LabeledPhone: Codable, Sendable {
        let label: String
        let number: String
    }

    struct LabeledEmail: Codable, Sendable {
        let label: String
        let address: String
    }

    var fullName: String {
        let name = [givenName, familyName].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? organizationName : name
    }
}

extension ContactRecord {
    /// The set of CNContactKeys needed to populate a ContactRecord.
    static let fetchKeys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactNicknameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    init(from contact: CNContact) {
        self.identifier = contact.identifier
        self.givenName = contact.givenName
        self.familyName = contact.familyName
        self.organizationName = contact.organizationName
        self.nickname = contact.nickname
        self.phoneNumbers = contact.phoneNumbers.map { entry in
            LabeledPhone(
                label: Self.humanizeLabel(entry.label),
                number: entry.value.stringValue
            )
        }
        self.emailAddresses = contact.emailAddresses.map { entry in
            LabeledEmail(
                label: Self.humanizeLabel(entry.label),
                address: entry.value as String
            )
        }
    }

    private static func humanizeLabel(_ label: String?) -> String {
        guard let label else { return "other" }
        return CNLabeledValue<NSString>.localizedString(forLabel: label).lowercased()
    }
}
