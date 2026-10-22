import ArgumentParser

@main
struct Contacts: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "contacts",
        abstract: "Search and browse your Apple Contacts from the terminal.",
        version: "0.1.0",
        subcommands: [
            Search.self,
            Lookup.self,
            List.self,
            Show.self,
        ],
        defaultSubcommand: Search.self
    )
}
