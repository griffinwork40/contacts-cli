# Apple Contacts Framework — CLI Reference

> macOS 10.11+ · Swift · `import Contacts`
>
> Source: Apple Developer Documentation (scraped 2026-10-22)

---

## Table of Contents

1. [Framework Overview](#1-framework-overview)
2. [CNContactStore — Authorization & Access](#2-cncontactstore--authorization--access)
3. [CNAuthorizationStatus — The Five States](#3-cnauthorizationstatus--the-five-states)
4. [Privacy / TCC — CLI-Specific Behaviour](#4-privacy--tcc--cli-specific-behaviour)
5. [CNContact — Full Property Reference](#5-cncontact--full-property-reference)
6. [Contact Keys — keysToFetch Constants](#6-contact-keys--keystofetch-constants)
7. [CNContactFetchRequest — Enumerating Contacts](#7-cncontactfetchrequest--enumerating-contacts)
8. [CNLabeledValue — Labels & Values](#8-cnlabeledvalue--labels--values)
9. [CNPhoneNumber](#9-cnphonenumber)
10. [CNPostalAddress](#10-cnpostaladdress)
11. [Search & Predicate Matching](#11-search--predicate-matching)
12. [CNContactFormatter & CNPostalAddressFormatter](#12-cncontactformatter--cnpostaladdressformatter)
13. [Swift Package Manager Setup](#13-swift-package-manager-setup)
14. [End-to-End Code Patterns](#14-end-to-end-code-patterns)
15. [Gotchas & CLI-Specific Notes](#15-gotchas--cli-specific-notes)

---

## 1. Framework Overview

The **Contacts** framework (available since macOS 10.11 / iOS 9) replaces the old AddressBook framework. It is:

- **Thread-safe** — all `CNContact`, `CNLabeledValue`, and `CNPhoneNumber` objects are immutable and safe to read from any thread.
- **Optimised for read-heavy workloads** — the fetch API is synchronous and blocking (do not call from the main thread in a GUI app; fine in a CLI).
- **Partial-contact model** — you declare exactly which properties you need at fetch time (`keysToFetch`). Accessing a property you did not request throws a runtime exception.
- **Unified contacts** — linked records from multiple accounts (iCloud, Exchange, etc.) are merged into a single `CNContact` by default.

```swift
import Contacts
```

No additional framework linking is needed in a Swift Package Manager target — just declare the dependency in `Package.swift` (see §13).

---

## 2. CNContactStore — Authorization & Access

```swift
class CNContactStore : NSObject
```

The single gateway to the contacts database. All fetch and save operations go through this object.

### 2.1 Requesting Access

```swift
// Async callback style (preferred — never blocks the calling thread)
let store = CNContactStore()
store.requestAccess(for: .contacts) { granted, error in
    if granted {
        // proceed
    } else {
        // handle denial
    }
}
```

`requestAccess(for:completionHandler:)` presents the system TCC prompt **the first time only**. On all subsequent calls it returns immediately with the cached decision.

### 2.2 Checking Status Without Prompting

```swift
let status = CNContactStore.authorizationStatus(for: .contacts)
// Returns CNAuthorizationStatus — see §3
```

Call this **before** `requestAccess` if you want to branch on already-denied or already-authorized without triggering a prompt.

### 2.3 Key Fetch Methods

| Method | Use case |
|--------|----------|
| `enumerateContacts(with:usingBlock:) throws` | Memory-efficient enumeration of **all** contacts matching a `CNContactFetchRequest`. Preferred for full scans. |
| `unifiedContacts(matching:keysToFetch:) throws -> [CNContact]` | Returns an array of contacts matching an `NSPredicate`. Good for targeted searches. |
| `unifiedContact(withIdentifier:keysToFetch:) throws -> CNContact` | Fetch a single contact by its stable `identifier` string. |
| `unifiedMeContactWithKeys(toFetch:) throws -> CNContact` | Fetch the "me" card (the user themselves). |

### 2.4 Info.plist / Entitlements

| Context | What you need |
|---------|---------------|
| **macOS app** (sandboxed) | `NSContactsUsageDescription` in `Info.plist` **+** `com.apple.security.personal-information.addressbook` entitlement |
| **macOS CLI / non-sandboxed** | `NSContactsUsageDescription` is **not** read from a CLI binary (no bundle). TCC prompt fires anyway — see §4. |
| **Notes access** | `com.apple.developer.contacts.notes` entitlement (requires provisioning profile; notes field is blank without it) |

---

## 3. CNAuthorizationStatus — The Five States

```swift
enum CNAuthorizationStatus : Int {
    case notDetermined  // 0 — never asked
    case restricted     // 1 — MDM/parental controls; user cannot change
    case denied         // 2 — user explicitly denied
    case authorized     // 3 — full access
    case limited        // 4 — user granted access to a curated subset only (macOS 13+)
}
```

**Handle all five states** in a CLI:

```swift
switch CNContactStore.authorizationStatus(for: .contacts) {
case .notDetermined:
    // call requestAccess — will show TCC prompt
case .authorized:
    // proceed immediately
case .limited:
    // proceed — but only a subset of contacts is visible
case .denied:
    fputs("Error: Contacts access denied. Grant access in System Settings → Privacy & Security → Contacts.\n", stderr)
    exit(1)
case .restricted:
    fputs("Error: Contacts access is restricted by a system policy.\n", stderr)
    exit(1)
@unknown default:
    fputs("Error: Unknown contacts authorization status.\n", stderr)
    exit(1)
}
```

---

## 4. Privacy / TCC — CLI-Specific Behaviour

### What happens when a CLI requests access

1. **First run**: macOS shows a system TCC (Transparency, Consent, and Control) alert: *"<binary name> would like to access your contacts."*
2. **Subsequent runs**: no prompt — the decision is cached per bundle ID (or binary path for un-bundled CLIs).
3. **Terminal.app proxy**: on macOS 10.14+, the Terminal (or iTerm2, etc.) may receive the TCC prompt on behalf of the child process. The user grants access to Terminal, not the CLI binary directly.
4. **Headless / SSH sessions**: if no window server is available, the TCC prompt **cannot be displayed** and access is denied silently. You must pre-authorize by running the tool interactively first.

### The `requestAccess` blocking quirk

`requestAccess(for:completionHandler:)` is **asynchronous** — it calls the completion block on an arbitrary queue. In a CLI (which has no run loop by default) you must synchronize:

```swift
import Contacts
import Foundation

let store = CNContactStore()
let sema = DispatchSemaphore(value: 0)
var accessGranted = false

store.requestAccess(for: .contacts) { granted, _ in
    accessGranted = granted
    sema.signal()
}
sema.wait()

guard accessGranted else {
    fputs("Contacts access denied.\n", stderr)
    exit(1)
}
```

Or use Swift Concurrency (requires macOS 12+):

```swift
let (granted, _) = try await store.requestAccess(for: .contacts)
```

### Resetting TCC for development

```bash
# Reset contacts TCC for your binary (requires SIP disabled or tccutil available)
tccutil reset Contacts com.yourapp.bundleid

# Or for Terminal-based tools, reset Terminal's contacts permission
tccutil reset Contacts com.apple.Terminal
```

---

## 5. CNContact — Full Property Reference

```swift
class CNContact : NSObject
```

Immutable. Use `CNMutableContact` (subclass) to create/modify. `CNContact` conforms to `NSCopying`, `NSMutableCopying`, `NSSecureCoding`, `Identifiable`, `Hashable`.

### 5.1 Identity

| Property | Type | Notes |
|----------|------|-------|
| `identifier` | `String` | Stable UUID-like string. Unique per device. Unified contacts have their own ID distinct from any linked contact's ID. |
| `contactType` | `CNContactType` | `.person` or `.organization` |

### 5.2 Name

| Property | Type |
|----------|------|
| `namePrefix` | `String` |
| `givenName` | `String` |
| `middleName` | `String` |
| `familyName` | `String` |
| `previousFamilyName` | `String` |
| `nameSuffix` | `String` |
| `nickname` | `String` |
| `phoneticGivenName` | `String` |
| `phoneticMiddleName` | `String` |
| `phoneticFamilyName` | `String` |

### 5.3 Organization / Work

| Property | Type |
|----------|------|
| `jobTitle` | `String` |
| `departmentName` | `String` |
| `organizationName` | `String` |
| `phoneticOrganizationName` | `String` |

### 5.4 Contact Info (Labeled Arrays)

| Property | Type |
|----------|------|
| `phoneNumbers` | `[CNLabeledValue<CNPhoneNumber>]` |
| `emailAddresses` | `[CNLabeledValue<NSString>]` |
| `postalAddresses` | `[CNLabeledValue<CNPostalAddress>]` |
| `urlAddresses` | `[CNLabeledValue<NSString>]` |
| `socialProfiles` | `[CNLabeledValue<CNSocialProfile>]` |
| `instantMessageAddresses` | `[CNLabeledValue<CNInstantMessageAddress>]` |
| `contactRelations` | `[CNLabeledValue<CNContactRelation>]` |

### 5.5 Dates

| Property | Type |
|----------|------|
| `birthday` | `DateComponents?` |
| `nonGregorianBirthday` | `DateComponents?` |
| `dates` | `[CNLabeledValue<NSDateComponents>]` |

### 5.6 Media

| Property | Type | Notes |
|----------|------|-------|
| `imageData` | `Data?` | Full-size profile picture |
| `thumbnailImageData` | `Data?` | Thumbnail version |
| `imageDataAvailable` | `Bool` | Check before fetching image data |

### 5.7 Notes

| Property | Type | Notes |
|----------|------|-------|
| `note` | `String` | Requires `com.apple.developer.contacts.notes` entitlement |

### 5.8 Key Availability Check (Partial Contact Safety)

Always check before accessing a property if you are not sure it was fetched:

```swift
if contact.isKeyAvailable(CNContactPhoneNumbersKey) {
    print(contact.phoneNumbers)
}

// Or for multiple keys at once:
if contact.areKeysAvailable([CNContactGivenNameKey, CNContactFamilyNameKey] as [CNKeyDescriptor]) {
    print("\(contact.givenName) \(contact.familyName)")
}
```

---

## 6. Contact Keys — keysToFetch Constants

These `String` constants (which also conform to `CNKeyDescriptor`) are passed to `keysToFetch`. **Only fetch what you need** — it improves performance significantly.

### Identity
```swift
CNContactIdentifierKey
CNContactTypeKey
```

### Name
```swift
CNContactNamePrefixKey
CNContactGivenNameKey
CNContactMiddleNameKey
CNContactFamilyNameKey
CNContactPreviousFamilyNameKey
CNContactNameSuffixKey
CNContactNicknameKey
CNContactPhoneticGivenNameKey
CNContactPhoneticMiddleNameKey
CNContactPhoneticFamilyNameKey
```

### Work
```swift
CNContactJobTitleKey
CNContactDepartmentNameKey
CNContactOrganizationNameKey
CNContactPhoneticOrganizationNameKey
```

### Contact Info
```swift
CNContactPhoneNumbersKey
CNContactEmailAddressesKey
CNContactPostalAddressesKey
CNContactUrlAddressesKey
CNContactSocialProfilesKey
CNContactInstantMessageAddressesKey
CNContactRelationsKey
```

### Dates
```swift
CNContactBirthdayKey
CNContactNonGregorianBirthdayKey
CNContactDatesKey
```

### Media
```swift
CNContactImageDataKey
CNContactThumbnailImageDataKey
CNContactImageDataAvailableKey
```

### Notes (requires entitlement)
```swift
CNContactNoteKey
```

### Formatter Descriptor Keys
These are not plain strings — they return `CNKeyDescriptor` objects:

```swift
CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
CNContactFormatter.descriptorForRequiredKeys(for: .phoneticFullName)
CNContact.descriptorForAllComparatorKeys()  // needed for sort comparators
```

### Casting to [CNKeyDescriptor]

```swift
// String constants need explicit cast to [CNKeyDescriptor]
let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactPhoneNumbersKey] as [CNKeyDescriptor]
```

---

## 7. CNContactFetchRequest — Enumerating Contacts

```swift
class CNContactFetchRequest : CNFetchRequest
```

Used exclusively with `CNContactStore.enumerateContacts(with:usingBlock:)`.

### 7.1 Initializer

```swift
let request = CNContactFetchRequest(keysToFetch: keys)
```

### 7.2 Properties

| Property | Type | Default | Notes |
|----------|------|---------|-------|
| `keysToFetch` | `[any CNKeyDescriptor]` | — | **Required.** Must include at least one key. |
| `predicate` | `NSPredicate?` | `nil` | Filter which contacts are enumerated. Use `CNContact` class methods to build (see §11). |
| `sortOrder` | `CNContactSortOrder` | `.none` | `.givenName` or `.familyName` |
| `unifyResults` | `Bool` | `true` | Merge linked contacts into unified contacts. |
| `mutableObjects` | `Bool` | `false` | Return `CNMutableContact` instead of `CNContact`. |

### 7.3 Enumerate All Contacts

```swift
let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactPhoneNumbersKey, CNContactEmailAddressesKey] as [CNKeyDescriptor]
let request = CNContactFetchRequest(keysToFetch: keys)

do {
    try store.enumerateContacts(with: request) { contact, stop in
        print("\(contact.givenName) \(contact.familyName)")
        // Set stop.pointee = true to abort early
    }
} catch {
    fputs("Fetch error: \(error)\n", stderr)
}
```

### 7.4 Enumerate with Predicate

```swift
let request = CNContactFetchRequest(keysToFetch: keys)
request.predicate = CNContact.predicateForContacts(matchingName: "Smith")
try store.enumerateContacts(with: request) { contact, _ in
    print(contact.givenName)
}
```

> **Important**: The Contacts framework does **not** support `NSCompoundPredicate` or generic/custom predicates. You must use only the predicates returned by `CNContact` class methods (§11).

---

## 8. CNLabeledValue — Labels & Values

```swift
class CNLabeledValue<ValueType> where ValueType : NSCopying, ValueType : NSSecureCoding
```

Wraps a contact property value with a descriptive label. Immutable and thread-safe.

### 8.1 Properties

| Property | Type | Notes |
|----------|------|-------|
| `label` | `String?` | Can be `nil` for unlabeled values. Use `CNLabeledValue.localizedString(forLabel:)` to get human-readable version. |
| `value` | `ValueType` | The actual value (e.g. `CNPhoneNumber`, `NSString`, `CNPostalAddress`) |
| `identifier` | `String` | Unique ID for this labeled value entry |

### 8.2 Common Label Constants

**General**
```swift
CNLabelHome        // "home"
CNLabelWork        // "work"
CNLabelSchool      // "school"
CNLabelOther       // "other"
```

**Phone-specific**
```swift
CNLabelPhoneNumberMobile      // "mobile"
CNLabelPhoneNumberiPhone      // "iPhone"
CNLabelPhoneNumberAppleWatch  // "Apple Watch"
CNLabelPhoneNumberMain        // "main"
CNLabelPhoneNumberHomeFax     // "home fax"
CNLabelPhoneNumberWorkFax     // "work fax"
CNLabelPhoneNumberOtherFax    // "other fax"
CNLabelPhoneNumberPager       // "pager"
```

**Email/URL**
```swift
CNLabelEmailiCloud            // "iCloud"
CNLabelURLAddressHomePage     // "homepage"
```

**Dates**
```swift
CNLabelDateAnniversary
```

### 8.3 Accessing Labeled Values

```swift
for labeledPhone in contact.phoneNumbers {
    let label = labeledPhone.label ?? "unknown"
    let humanLabel = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: label)
    let number = labeledPhone.value.stringValue
    print("  \(humanLabel): \(number)")
}

for labeledEmail in contact.emailAddresses {
    let email = labeledEmail.value as String
    let label = CNLabeledValue<NSString>.localizedString(forLabel: labeledEmail.label ?? "")
    print("  \(label): \(email)")
}
```

### 8.4 Custom Labels

Custom labels are stored as arbitrary strings. They do **not** match the predefined constants. Check with:

```swift
if labeledPhone.label == CNLabelPhoneNumberMobile {
    // predefined label
} else {
    // custom label — display as-is or via localizedString
}
```

---

## 9. CNPhoneNumber

```swift
class CNPhoneNumber : NSObject
```

Immutable. Stores a phone number as a raw string — **no formatting logic is applied** by the framework itself.

### Properties / Methods

| Symbol | Notes |
|--------|-------|
| `init(stringValue: String)` | Create from any string, e.g. `"(408) 555-0126"`, `"+14085550126"` |
| `var stringValue: String` | Returns the string exactly as stored — no normalization |
| `CNContactPhoneNumbersKey` | The fetch key to use to get phone numbers |

> **Formatting**: The framework stores `stringValue` verbatim. To normalize or format numbers (E.164, national format, etc.) you need a third-party library like `PhoneNumberKit` — the Contacts framework has no built-in formatter for phone numbers (only `CNContactFormatter` for names and `CNPostalAddressFormatter` for addresses).

### Usage

```swift
let phone = CNPhoneNumber(stringValue: "+1 (408) 555-0126")
print(phone.stringValue)  // "+1 (408) 555-0126"
```

---

## 10. CNPostalAddress

```swift
class CNPostalAddress : NSObject
```

Immutable. Use `CNMutablePostalAddress` to construct addresses.

### Properties

| Property | Type | Notes |
|----------|------|-------|
| `street` | `String` | Full street line (may include apt/suite) |
| `city` | `String` | City name |
| `state` | `String` | State / province / region |
| `postalCode` | `String` | ZIP / postal code |
| `country` | `String` | Country name |
| `isoCountryCode` | `String` | ISO 3166-1 alpha-2 (e.g. `"US"`, `"GB"`) |
| `subAdministrativeArea` | `String` | County / district |
| `subLocality` | `String` | Neighborhood / sub-city |

### Formatting

```swift
let formatter = CNPostalAddressFormatter()
let formatted = formatter.string(from: address)
// Returns a locale-appropriate multiline string
```

### Key Constants (for keysToFetch sub-keys)
```swift
CNPostalAddressStreetKey
CNPostalAddressCityKey
CNPostalAddressStateKey
CNPostalAddressPostalCodeKey
CNPostalAddressCountryKey
CNPostalAddressISOCountryCodeKey
```

---

## 11. Search & Predicate Matching

> **Constraint**: Only the predicates returned by `CNContact` class methods work with `CNContactStore` and `CNContactFetchRequest`. You **cannot** compose them with `NSCompoundPredicate`.

### Available Predicates

```swift
// By name (partial match — "Smith" matches "John Smith", "Smithson", etc.)
CNContact.predicateForContacts(matchingName: "Smith")

// By phone number (CNPhoneNumber object)
CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: "4085550126"))

// By email address (exact match, case-insensitive)
CNContact.predicateForContacts(matchingEmailAddress: "john@example.com")

// By identifiers (array of identifier strings)
CNContact.predicateForContacts(withIdentifiers: ["id1", "id2"])

// By group membership
CNContact.predicateForContactsInGroup(withIdentifier: groupID)

// By container
CNContact.predicateForContactsInContainer(withIdentifier: containerID)
```

### Phone Number Matching

The `predicateForContacts(matching:CNPhoneNumber)` predicate does **fuzzy** digit-based matching — it normalizes the number before comparing, so `"(408) 555-0126"` matches `"4085550126"`. You still need to pass a `CNPhoneNumber` object (not a raw string).

### Predicate-based Fetch (unifiedContacts)

```swift
let keys = [CNContactGivenNameKey, CNContactFamilyNameKey,
            CNContactEmailAddressesKey] as [CNKeyDescriptor]
let predicate = CNContact.predicateForContacts(matchingEmailAddress: "john@example.com")
let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
```

### Full Scan with In-Process Filtering

When you need compound queries (name AND phone number, etc.), do a full enumeration and filter in Swift:

```swift
let request = CNContactFetchRequest(keysToFetch: keys)
var results: [CNContact] = []

try store.enumerateContacts(with: request) { contact, _ in
    let hasEmail = contact.emailAddresses.contains {
        ($0.value as String).lowercased().contains("apple.com")
    }
    if hasEmail { results.append(contact) }
}
```

---

## 12. CNContactFormatter & CNPostalAddressFormatter

### Name Formatting

```swift
// Full name (respects locale name-order preferences)
let fullName = CNContactFormatter.string(from: contact, style: .fullName)

// Phonetic full name
let phoneticName = CNContactFormatter.string(from: contact, style: .phoneticFullName)

// As an attributed string (with per-component attributes)
let attrStr = CNContactFormatter().attributedString(from: contact, style: .fullName, defaultAttributes: nil)
```

Required key descriptor for formatter operations:
```swift
let formatterKey = CNContactFormatter.descriptorForRequiredKeys(for: .fullName)
// Include in keysToFetch alongside your other keys
```

### Postal Address Formatting

```swift
let formatter = CNPostalAddressFormatter()
let formatted = formatter.string(from: postalAddress)
// or attributed:
let attrStr = formatter.attributedString(from: postalAddress, withDefaultAttributes: nil)
```

### Localized Property Names

```swift
// "Phone" → "Téléphone" in French locale
let label = CNContact.localizedString(forKey: CNContactPhoneNumbersKey)

// "home" → "casa" in Spanish locale
let homeLabel = CNLabeledValue<NSString>.localizedString(forLabel: CNLabelHome)
```

---

## 13. Swift Package Manager Setup

### Package.swift

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "contacts-cli",
    platforms: [
        .macOS(.v13)   // or .v12 / .v11 — minimum for Contacts is macOS 10.11
    ],
    targets: [
        .executableTarget(
            name: "contacts-cli",
            path: "Sources/contacts-cli",
            // No explicit dependency entry needed — Contacts is a system framework.
            // Link it via linkerSettings:
            linkerSettings: [
                .linkedFramework("Contacts")
            ]
        )
    ]
)
```

> **Note**: On macOS you can also just `import Contacts` and SPM picks it up via the SDK without the explicit `linkerSettings` in most Xcode/SwiftPM versions. If you get linker errors, add the `linkedFramework` line above.

### Directory Layout

```
contacts-cli/
├── Package.swift
└── Sources/
    └── contacts-cli/
        └── main.swift
```

### Entitlements for Sandboxed Builds

If you ever sign and sandbox the binary, you need an `.entitlements` file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.personal-information.addressbook</key>
    <true/>
    <!-- Only if you need to read the notes field: -->
    <!-- <key>com.apple.developer.contacts.notes</key>  -->
    <!-- <true/>                                        -->
</dict>
</plist>
```

Apply during code signing:
```bash
codesign --sign - --entitlements contacts-cli.entitlements .build/release/contacts-cli
```

---

## 14. End-to-End Code Patterns

### Pattern A — Full Scan with Semaphore (macOS CLI)

```swift
import Contacts
import Foundation

func fetchAllContacts() throws -> [CNContact] {
    let store = CNContactStore()

    // 1. Request / verify access
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .notDetermined {
        let sema = DispatchSemaphore(value: 0)
        var granted = false
        store.requestAccess(for: .contacts) { g, _ in granted = g; sema.signal() }
        sema.wait()
        guard granted else { throw ContactsError.denied }
    } else if status != .authorized && status != .limited {
        throw ContactsError.denied
    }

    // 2. Build request
    let keys: [CNKeyDescriptor] = [
        CNContactIdentifierKey as CNKeyDescriptor,
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
        CNContactPostalAddressesKey as CNKeyDescriptor,
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
    ]
    let request = CNContactFetchRequest(keysToFetch: keys)
    request.sortOrder = .familyName

    // 3. Enumerate
    var contacts: [CNContact] = []
    try store.enumerateContacts(with: request) { contact, _ in
        contacts.append(contact)
    }
    return contacts
}

enum ContactsError: Error {
    case denied
}
```

### Pattern B — Targeted Search

```swift
func searchByName(_ name: String, store: CNContactStore) throws -> [CNContact] {
    let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]
    let predicate = CNContact.predicateForContacts(matchingName: name)
    return try store.unifiedContacts(matching: predicate, keysToFetch: keys)
}
```

### Pattern C — Printing a Contact

```swift
func printContact(_ contact: CNContact) {
    let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "(no name)"
    print("Name: \(name)")
    print("ID:   \(contact.identifier)")

    for phone in contact.phoneNumbers {
        let label = CNLabeledValue<CNPhoneNumber>.localizedString(forLabel: phone.label ?? "")
        print("  📞 \(label): \(phone.value.stringValue)")
    }

    for email in contact.emailAddresses {
        let label = CNLabeledValue<NSString>.localizedString(forLabel: email.label ?? "")
        print("  📧 \(label): \(email.value as String)")
    }

    for addr in contact.postalAddresses {
        let label = CNLabeledValue<CNPostalAddress>.localizedString(forLabel: addr.label ?? "")
        let formatted = CNPostalAddressFormatter().string(from: addr.value)
            .replacingOccurrences(of: "\n", with: ", ")
        print("  🏠 \(label): \(formatted)")
    }
}
```

### Pattern D — Fetch Single Contact by Identifier

```swift
func fetchContact(id: String, store: CNContactStore) throws -> CNContact {
    let keys: [CNKeyDescriptor] = [
        CNContactGivenNameKey as CNKeyDescriptor,
        CNContactFamilyNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]
    return try store.unifiedContact(withIdentifier: id, keysToFetch: keys)
}
```

---

## 15. Gotchas & CLI-Specific Notes

### 1. Partial Contact Exception (Most Common Bug)

Accessing any property **not included in `keysToFetch`** throws:
```
*** Terminating app due to uncaught exception 'CNPropertyNotFetchedException'
```
Always declare every key you access. Use `isKeyAvailable(_:)` / `areKeysAvailable(_:)` as a safety net.

### 2. No Compound Predicates

`CNContactStore` only accepts predicates created by the `CNContact` class methods. Do not try:
```swift
// ❌ This will throw at runtime
NSCompoundPredicate(andPredicateWithSubpredicates: [pred1, pred2])
```
Do compound filtering in Swift after fetching.

### 3. Phone Number Predicate Requires CNPhoneNumber Object

```swift
// ❌ Wrong
CNContact.predicateForContacts(matchingName: "4085550126")  // won't match numbers

// ✅ Correct
CNContact.predicateForContacts(matching: CNPhoneNumber(stringValue: "4085550126"))
```

### 4. `stringValue` is Raw — No Normalization

`CNPhoneNumber.stringValue` returns exactly what was stored. Two contacts with the same number may store it differently (`+14085550126` vs `(408) 555-0126`). Normalize before comparison.

### 5. Notes Field Requires Entitlement

The `note` property is always empty without the `com.apple.developer.contacts.notes` entitlement. This entitlement requires a provisioning profile (Apple Developer Program membership). **It is not available for ad-hoc unsigned CLIs**.

### 6. TCC Prompt Can't Show in Headless Sessions

In SSH/CI/daemon contexts with no window server, `requestAccess` silently returns `denied`. Pre-authorize interactively:
```bash
# Run interactively once to trigger the TCC prompt
./contacts-cli --list
```

### 7. The `limited` Status (macOS 13+)

When status is `.limited`, the contacts store only returns the subset the user selected in the contacts picker. Your enumeration will appear to work, but will silently omit contacts. Handle this case explicitly — inform the user and suggest re-granting full access in System Settings.

### 8. Unified Contact Identifiers vs Linked Contact Identifiers

When you refetch, **always use the unified contact's `identifier`**, not any identifier from a linked individual record. Unified identifiers are ephemeral to the merge — they can change if the user unlinks records.

### 9. `enumerateContacts` vs `unifiedContacts`

- `enumerateContacts` is **streaming** — memory-efficient for large address books.
- `unifiedContacts` loads **all matching results into an array** — fine for small result sets (e.g. a name search), but avoid for full database scans.

### 10. Background Thread Recommendation

Both `enumerateContacts` and `unifiedContacts` perform disk I/O and block. In a CLI this is fine since you control the thread. In a GUI app, always dispatch to a background queue.

### 11. CNContactStoreDidChange Notification

If your CLI runs in a long-lived loop or caches contacts, observe:
```swift
NotificationCenter.default.addObserver(
    forName: .CNContactStoreDidChange,
    object: nil,
    queue: nil
) { _ in
    // Invalidate cached contacts and refetch
}
```

---

## Quick Reference Card

```
Authorization flow (CLI):
  authorizationStatus → .notDetermined → requestAccess (show TCC prompt)
                      → .authorized / .limited → fetch
                      → .denied / .restricted → exit with message

Fetch flow:
  CNContactStore
    └── enumerateContacts(with: CNContactFetchRequest)   ← full scan
    └── unifiedContacts(matching: NSPredicate, ...)      ← predicate search  
    └── unifiedContact(withIdentifier: id, ...)          ← single by ID

Key types:
  CNContact.phoneNumbers        → [CNLabeledValue<CNPhoneNumber>]
    .value.stringValue            → "+1 (408) 555-0126"
    .label                        → CNLabelPhoneNumberMobile etc.

  CNContact.emailAddresses      → [CNLabeledValue<NSString>]
    .value as String              → "john@example.com"

  CNContact.postalAddresses     → [CNLabeledValue<CNPostalAddress>]
    .value.street / .city / .state / .postalCode / .country

Predicates (only these work):
  CNContact.predicateForContacts(matchingName:)
  CNContact.predicateForContacts(matching: CNPhoneNumber)
  CNContact.predicateForContacts(matchingEmailAddress:)
  CNContact.predicateForContacts(withIdentifiers:)
  CNContact.predicateForContactsInGroup(withIdentifier:)
  CNContact.predicateForContactsInContainer(withIdentifier:)
```
