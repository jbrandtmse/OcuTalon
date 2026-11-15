# A Jira MCP server, step by step

This example adds a Jira MCP server to OcuTalon on your own install, classifies its tools, runs a search, approves a change and sets up a source that polls for new tickets. Then it explains how OcuTalon governs MCP tools. MCP servers are off on the online demo: nobody can add one there, and OcuTalon reaches none.

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

## 4. Poll new tickets assigned to you as a source

A Read-only tool can also be a source: OcuTalon calls it on a schedule, makes an attention decision on each new result, and lists the source on your digest's coverage list. Only a Read-only tool can be a source, and sources are off on the online demo.

In the Tools table, press **Use as a source** on the `search_issues` row, fill in the fields under **Use as a source**, then press **Save changes**:

- **Source name**: `Jira tickets`. A source's name is 1 to 100 characters, and it can't be "Mailbox" in any letter case: that is the name your digest gives the connected mailbox.
- **Arguments (JSON)**: the arguments of your server's search tool, as a JSON object. For the newest tickets assigned to you, for example: `{"jql": "assignee = currentUser() ORDER BY created DESC", "maxResults": 5}`. The arguments go to the server with every call, so put no secret in them; OcuTalon refuses a `secret://` reference there.
- **Check every**: 15 minutes. The choices are 5 minutes, 15 minutes, 30 minutes, 1 hour, 6 hours and 1 day.

The source then shows under **Your sources**, and under Background checks its row reads "Polled every 15 minutes", with its last run, its result and a link to its trace. To change the source, save it again with the same name. **Remove** removes it, and removing the server removes its sources too.

Each poll is one call of `call_mcp_tool`, through the same gate as a call from the chat, with the same audit entry, and shows as the step "Running search_issues on Jira" in Visual Trace. The poll itself asks no model; only a new item's attention decision does. OcuTalon polls the source at its next background check, which comes every minute, and then every 15 minutes:

- The first poll that gets an answer sets a baseline: OcuTalon keeps a hash of the answer and sends nothing.
- A later answer that differs from each of the 50 newest different answers becomes one item, with the whole answer as its text, and OcuTalon makes an attention decision on it. The item and its decision show in Visual Trace. An answer that matches one of them, or an empty answer, sends nothing.
- OcuTalon compares whole answers, not tickets: an answer that changed for another reason than a new ticket also becomes a new item. Even a long answer is compared whole, so a change anywhere in it makes a new item, but a long answer is cut in the item, as any tool's result is. Keep the answer short, for example with `maxResults`, so that the item holds all of it.
- Each item is untrusted content, as every result of an MCP tool is.
- Saving the source with another tool or other arguments starts it over, with a new baseline. Changing only how often it is checked keeps its hashes.
- OcuTalon runs one source's poll at a time for the whole install, so when several sources are due together, the others wait for a later minute.
- If the tool is classified Risky or Unclassified, or its description or inputs change, the source stops polling at its next due time: OcuTalon makes no call, and every admin gets this notice once: "The source Jira tickets stopped polling at 09:15, because its tool search_issues on Jira is no longer Read-only. Your digest lists it as not checked." Once you classify the tool Read-only again, the source polls again at its next due time.

### The source on your digest

Your digest's coverage list names the source as you typed it: "Passed: Jira tickets (at 09:15)." Only the polls since you set the source up, or last gave it another tool or other arguments, count. The source counts as checked only when its latest poll passed and it kept to its schedule: the time between two of its polls, and from its last poll to the digest, may be at most its interval plus 3 minutes, or plus 2 minutes for each source on this install that isn't stopped, when that is longer. Otherwise the source is not checked, and the digest gives the reason, for example:

| What happened | The digest's line |
| --- | --- |
| OcuTalon couldn't reach the server | Not checked: Jira tickets (unreachable since 09:15). |
| The server didn't answer in time | Not checked: Jira tickets (the check timed out at 09:15). |
| The call failed for another reason | Not checked: Jira tickets (the check stopped with an error at 09:15). |
| The tool is no longer Read-only | Not checked: Jira tickets (stopped polling at 09:15: its tool is no longer Read-only). |
| A poll came too late | Not checked: Jira tickets (the check didn't run between 09:00 and 09:30). |
| The last poll is too old | Not checked: Jira tickets (its last check was at 08:30, too long ago to count). |

A source that isn't checked is named before every entry that passed, the page opens its "What I checked" list, and the digest never says "Everything I checked passed."

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
