# contacts-cli

Search and browse your Apple Contacts from the terminal.

## Why

Apple Contacts is locked inside a GUI. This tool breaks it out so you can resolve names to phone numbers and email addresses in shell pipelines — particularly useful alongside CLI tools like `imsg` (iMessage) and `gog` (Gmail) where you want to pass a contact's number or address without copy-pasting from the app.

```sh
# Who's this number?
contacts lookup --phone "+15555550100"

# Get a contact's mobile number into a variable
NUMBER=$(contacts search "Jane Doe" --format json | jq -r '.[0].phoneNumbers[] | select(.label=="mobile") | .number')
imsg send "$NUMBER" "On my way"

# Draft an email to a contact
EMAIL=$(contacts search "John Smith" --format json | jq -r '.[0].emailAddresses[0].address')
gog send "$EMAIL" --subject "Hey" --body "See you at 3"
```

## Install

```sh
swift build -c release
cp .build/release/contacts-cli /opt/homebrew/bin/contacts
```

## Commands

### `search` — find contacts by name

```sh
contacts search "Jane"
contacts search "Jane Doe"
contacts search "Doe" --format json
```

Default subcommand — `contacts "Jane"` works too.

### `lookup` — reverse-lookup by phone or email

```sh
contacts lookup --phone "+15555550100"
contacts lookup --email "jane@example.com"
contacts lookup --phone "555-0100" --format json
```

Strips non-numeric characters before matching, so partial numbers work.

### `list` — dump all contacts

```sh
contacts list
contacts list --limit 20
contacts list --format json
```

Sorted by family name.

### `show` — full detail for one contact by ID

```sh
contacts show "A1B2C3D4-..."
contacts show "A1B2C3D4-..." --format json
```

The `id:` field in `search`/`list` text output (and `identifier` in JSON) is the stable CNContact identifier to pass here.

## Output formats

**Text** (default) — human-readable, one contact per block:

```
Jane Doe
  org: Acme Corp
  mobile: +1 (555) 555-0100
  home: jane@example.com
  id: A1B2C3D4-E5F6-...
```

**JSON** (`--format json`) — pretty-printed array of objects, sorted keys:

```json
[
  {
    "emailAddresses": [
      { "address": "jane@example.com", "label": "home" }
    ],
    "familyName": "Doe",
    "givenName": "Jane",
    "identifier": "A1B2C3D4-E5F6-...",
    "nickname": "",
    "organizationName": "Acme Corp",
    "phoneNumbers": [
      { "label": "mobile", "number": "+1 (555) 555-0100" }
    ]
  }
]
```

## jq integration examples

```sh
# First mobile number for a contact
contacts search "Jane Doe" --format json \
  | jq -r '.[0].phoneNumbers[] | select(.label=="mobile") | .number'

# All email addresses for everyone at a company
contacts list --format json \
  | jq -r '.[] | select(.organizationName=="Acme Corp") | .emailAddresses[].address'

# Build a name→email map
contacts list --format json \
  | jq 'map({(.givenName + " " + .familyName): .emailAddresses[0].address}) | add'
```

## TCC / Contacts access

`contacts` first tries `CNContactStore` (the native Contacts framework). On a fresh install your terminal app may not have Contacts permission yet — macOS will prompt for it on first run.

If permission is denied or cannot be granted (e.g. the binary is unsigned and TCC refuses to prompt), the tool **automatically falls back to AppleScript/JXA** via `osascript`, routing through `Contacts.app` which holds its own system-level access. You'll see `(using Contacts.app fallback)` on stderr when this happens — stdout is unaffected and all four commands work normally.

To grant direct access instead: **System Settings → Privacy & Security → Contacts** and enable your terminal app.

## Requirements

- macOS 13+
- Swift 5.9+
