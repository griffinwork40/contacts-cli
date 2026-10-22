import ArgumentParser

struct Show: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show full details for a contact by identifier."
    )

    @Argument(help: "Contact identifier (from search or list output).")
    var identifier: String

    @Option(name: .shortAndLong, help: "Output format (text or json).")
    var format: OutputFormat = .text

    func run() throws {

        guard let record = try ContactsAccess.show(identifier: identifier) else {
            throw ValidationError("No contact found with identifier '\(identifier)'.")
        }

        print(OutputFormatter.format(record, as: format))
    }
}
