import Foundation

public typealias MCPToolResult = (text: String, isError: Bool)

/// An optional tool. Its handler receives the library after the server applies its scope filter.
public struct MCPTool {
    public let name: String
    public let definition: [String: Any]
    let handler: ([String: Any], ConversationLibrary) -> MCPToolResult

    public init(name: String, description: String, properties: [String: Any], required: [String],
                handler: @escaping ([String: Any], ConversationLibrary) -> MCPToolResult) {
        self.name = name
        self.definition = [
            "name": name, "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required] as [String: Any],
        ]
        self.handler = handler
    }
}
