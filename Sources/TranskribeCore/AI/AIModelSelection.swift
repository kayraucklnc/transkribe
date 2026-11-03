/// Selects a replacement when the selected model is unavailable.
public enum AIModelSelection {
    /// OpenRouter selections remain selected when unavailable. xAI and OpenRouter require an explicit selection.
    public static func automaticFallback(models: [AIModel], availability: [AIProviderKind: AIAvailability],
                                         selectedModel: AIModel? = nil) -> AIModel? {
        guard selectedModel?.provider != .openRouter else { return nil }
        return models.first {
            $0.provider != .xai && $0.provider != .openRouter && availability[$0.provider]?.isAvailable == true
        }
    }
}
