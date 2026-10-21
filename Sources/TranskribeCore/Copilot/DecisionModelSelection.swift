public enum DecisionModelSelection {
    /// Returns only the selected provider. Unavailable models have no replacement.
    public static func provider(for model: AIModel, providers: [any AIProvider],
                                availability: [AIProviderKind: AIAvailability]) -> (any AIProvider)? {
        guard availability[model.provider]?.isAvailable == true else { return nil }
        return providers.first { provider in
            provider.kind == model.provider && provider.models.contains { $0.provider == model.provider && $0.id == model.id }
        }
    }
}
