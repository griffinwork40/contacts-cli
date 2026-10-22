import ArgumentParser

struct List: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List all contacts."
    )

    @Option(name: .shortAndLong, help: "Maximum number of contacts to show.")
    var limit: Int?

    @Option(name: .shortAndLong, help: "Output format (text or json).")
    var format: OutputFormat = .text

    func run() throws {

        var results = try ContactsAccess.listAll()

        if let limit {
            results = Array(results.prefix(limit))
        }

        print(OutputFormatter.format(results, as: format))
    }
}
