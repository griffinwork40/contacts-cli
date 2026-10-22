import ArgumentParser

struct Lookup: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Look up contacts by phone number or email address."
    )

    @Option(name: .shortAndLong, help: "Phone number to look up.")
    var phone: String?

    @Option(name: .shortAndLong, help: "Email address to look up.")
    var email: String?

    @Option(name: .shortAndLong, help: "Output format (text or json).")
    var format: OutputFormat = .text

    func validate() throws {
        guard phone != nil || email != nil else {
            throw ValidationError("Provide --phone or --email to look up.")
        }
    }

    func run() throws {

        var results: [ContactRecord] = []

        if let phone {
            results.append(contentsOf: try ContactsAccess.lookup(phone: phone))
        }
        if let email {
            results.append(contentsOf: try ContactsAccess.lookup(email: email))
        }

        print(OutputFormatter.format(results, as: format))
    }
}
