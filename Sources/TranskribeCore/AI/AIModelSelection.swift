/// Selects a replacement when the selected model is unavailable.
public enum AIModelSelection {
    /// xAI requires an explicit selection. Other providers keep their existing order.
    public static func automaticFallback(models: [AIModel], availability: [AIProviderKind: AIAvailability]) -> AIModel? {
        models.first { $0.provider != .xai && availability[$0.provider]?.isAvailable == true }
    }
}
