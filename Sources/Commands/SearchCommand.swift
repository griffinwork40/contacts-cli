import ArgumentParser

struct Search: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Search contacts by name."
    )

    @Argument(help: "Name to search for (first, last, or full name).")
    var query: String

    @Option(name: .shortAndLong, help: "Output format (text or json).")
    var format: OutputFormat = .text

    func run() throws {
        let results = try ContactsAccess.search(name: query)
        print(OutputFormatter.format(results, as: format))
    }
}

extension OutputFormat: ExpressibleByArgument {}
