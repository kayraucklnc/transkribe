import Foundation

/// These counts estimate one token per four characters. They are not provider billing totals.
public struct IntentTokenUsage: Equatable, Sendable {
    public var input = 0
    public var output = 0
    public var total: Int { input + output }
}

public actor IntentTokenCounter {
    private var counts = IntentTokenUsage()

    public init() {}

    public func usage() -> IntentTokenUsage { counts }

    public func record(inputCharacters: Int, outputCharacters: Int) {
        counts.input += (max(0, inputCharacters) + 3) / 4
        counts.output += (max(0, outputCharacters) + 3) / 4
    }
}

/// Use the same counter for a meeting's decision provider and action providers.
public struct IntentMeteredProvider: AIProvider {
    public var kind: AIProviderKind { base.kind }
    public var models: [AIModel] { base.models }
    private let base: any AIProvider
    private let counter: IntentTokenCounter

    public init(base: any AIProvider, counter: IntentTokenCounter) {
        self.base = base
        self.counter = counter
    }

    public func stream(model: AIModel, system: String, messages: [AIMessage]) -> AsyncThrowingStream<String, Error> {
        AIStreaming.run { yield in
            let input = messages.reduce(system.count) { $0 + $1.text.count }
            var output = 0
            do {
                try Task.checkCancellation()
                for try await delta in base.stream(model: model, system: system, messages: messages) {
                    try Task.checkCancellation()
                    output += delta.count
                    yield(delta)
                }
                await counter.record(inputCharacters: input, outputCharacters: output)
            } catch {
                await counter.record(inputCharacters: input, outputCharacters: output)
                throw error
            }
        }
    }

    public func contextCharacterBudget(for model: AIModel) -> Int { base.contextCharacterBudget(for: model) }
    public func availability() async -> AIAvailability { await base.availability() }
}
