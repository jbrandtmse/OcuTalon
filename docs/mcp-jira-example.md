# A Jira MCP server, step by step

This example adds a Jira MCP server to OcuTalon on your own install, classifies its tools, runs a search and approves a change. Then it explains how OcuTalon governs MCP tools. MCP servers are off on the online demo: nobody can add one there, and OcuTalon reaches none.

## What you need

- OcuTalon on your own install, and an account that holds the OcuTalonAdmin role, such as the README account.
- A Jira MCP server that OcuTalon can reach over HTTPS, and the token it expects, if it expects one. Plain HTTP works only to this computer, for development.

The tool names below are examples. Your server's names may differ: classify each tool by what it does.

## 1. Add the server

In Settings > Tools and MCP servers, fill in the fields under **Add server**, then press the **Add server** button:

- **Name**: `Jira`. An MCP server's name is a letter followed by up to 39 letters, digits or underscores.
- **Address**: the server's address, for example `https://jira-mcp.example.com/mcp`.
- **Secret (optional)**: the server's token. Sent to the server with every request. It is kept in the IRIS Wallet and never shown again.

OcuTalon keeps the secret in the IRIS Wallet and writes the server's Config Store entry, `AI.MCP.OcuTalon_Jira`, with the address and a `secret://` reference to the secret, never the secret itself. No message, log, audit entry or answer holds the secret. Adding the server also creates its own IRIS resource, `OcuTalon_MCP_Jira`, which OcuTalon's service user must hold for every call of the server's tools. Removing the server removes the resource, the entry and the secret.

## 2. Classify its tools

The server's tools show in the Tools table once OcuTalon next uses its agents, and they count as risky until you classify them. Each tool's control offers Unclassified (counts as risky), Read-only and Risky. For a Jira server:

| Tool (example) | What it does | Classify it |
| --- | --- | --- |
| `search_issues` | searches tickets | Read-only |
| `get_issue` | reads one ticket | Read-only |
| `create_issue` | creates a ticket | Risky |
| `update_issue` | changes a ticket | Risky |
| `add_comment` | comments on a ticket | Risky |

Classify a tool Read-only only when it reads and changes nothing.

An MCP tool that runs operating-system commands or arbitrary code must be classified Risky.

A Read-only MCP tool still sends its arguments to its server, even in turns that read untrusted content, so classify a tool Read-only only when you trust its server with what OcuTalon reads.

If the server offers a tool with the same name as one of OcuTalon's own tools, or one named `call_mcp_tool`, OcuTalon refuses it: the Tools table shows "Refused: a built-in tool has this name", admins get a notice, and the tool is never offered or run.

## 3. Search, then approve a change

In the chat, ask "Find the Jira tickets assigned to me." The search tool is Read-only, so it runs at once. In Visual Trace the call shows as the step "Running search_issues on Jira".

Then ask "Add a comment to OPS-12 saying the feed is fixed." The comment tool is Risky, so nothing runs yet. The chat shows an approval request that reads "Run add_comment on Jira", says why it waits, lists each of its inputs on a line of its own and ends with "No dry run is available for this tool. Approving runs exactly this call once." **Approve** runs exactly that call once, and **Reject** runs nothing. A request that nobody answers within 24 hours expires.

If an admin removes the server while a request for one of its tools is waiting, the request is cancelled and nothing runs.

## How OcuTalon governs MCP tools

- Only admins add or remove a server or classify its tools, only from the settings page.
- A new tool, and a tool whose description or inputs changed, is Unclassified, which counts as risky. OcuTalon identifies a tool by its server and its name, and ignores MCP annotations such as `readOnlyHint`.
- Every call goes through one governed tool, `call_mcp_tool`, and passes the same gate as OcuTalon's built-in tools. Before every call, OcuTalon checks that the tool still has the name, description and inputs it was classified with, and runs nothing if it changed.
- In your own turns, a Read-only tool runs at once, and a Risky or Unclassified tool waits for your approval. In a turn that holds content that didn't come from you, such as an email or an MCP tool's result, only Read-only tools run: any other call is denied, and no approval request is raised.
- A tool's results are untrusted content: they can never approve, classify, change a setting or add a server.
- Each call of a server's tool that runs writes an audit entry with the server, the tool and the outcome, never its arguments or its result, and shows as a step in Visual Trace.

The security overview's [MCP tools](security-overview.md#mcp-tools) section lists the same rules.

## Time limits

OcuTalon's time limits for MCP servers are not hard deadlines. A server has 2 seconds to answer OcuTalon's check before a request offers its tools, and each listing of its tools, and 20 seconds to answer a tool call. Each limit applies to each wait for data and starts again whenever the server sends some, so a slow server can hold a request longer: in a test against a server that sent one byte a second, the 2-second check took 31 seconds and a 20-second call 36 seconds. A server that stops answering in the middle of a request, after its check passed, holds that request until it closes the connection.
