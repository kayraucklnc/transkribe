import TranskribeCore

// Model Context Protocol server over stdio, started by AI clients (e.g. Claude Code) so they
// can search and read the user's conversations. The library is re-read on each call, so new
// transcripts show up without restarting.
MCPServer(library: { ConversationLibrary.load() }).run()
