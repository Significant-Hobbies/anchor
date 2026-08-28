# MCP and export

Two ways out of the app: files you can open, and a server an AI can query.

## MCP server

`anchor-mcp` speaks JSON-RPC 2.0 over stdio — the transport MCP clients expect.
The repository builds it as a developer tool; it is not currently bundled with
the signed Mac app. macOS protects Anchor's app-group store, so a terminal or MCP
client may need user-granted Full Disk Access before the tool can read that store.
The server opens it with CloudKit off and never writes to it.

```bash
swift build -c release
codex mcp add anchor -- "$PWD/.build/release/anchor-mcp"
```

Anchor deliberately does not show this command in Settings until the release app
can provide a signed, app-mediated bridge to its protected store.

### Tools

| Tool | Answers |
| --- | --- |
| `focus_overview` | Hours focused, sessions, completion rate, interruption rate, streaks |
| `list_sessions` | Recent sessions with goal, project, tags, entry notes, length, outcome, and interruptions |
| `distraction_patterns` | Counts by category, internal/external split, break rates, recurring themes |
| `goal_progress` | Time and interruptions per goal |
| `best_hours` | Focused time and interruptions by hour of day |
| `search_distractions` | Free-text search across notes, saved tags, keywords and categories |
| `work_patterns` | Project, tag, billing and distraction-timing breakdowns |
| `machine_presence` | Aggregate active, tracked and untracked computer time |
| `daily_review` | One day's planned and timed-observed time, untimed completion count, largest gaps, causal evidence, and suggestions — never an adherence score |
| `export_workbook` | Writes an `.xlsx` to a path you give it |

History tools take an optional `since_days`; `daily_review` takes `days_ago`.
Everything except `export_workbook` is read-only; the server never mutates your
history.

### Diagnostics

```bash
anchor-mcp --diagnose
```

Reports whether Apple Intelligence is usable here, which store is in use, and how
a fixed set of sample notes actually get categorised. Tagging quality is otherwise
invisible until it has already mislabelled a week of your data. Expect `8/8` and
`4/4`; anything less means a prompt regressed.

## Export formats

`.xlsx`, sessions CSV, distractions CSV, day-plan CSV, schedule-change CSV, and
JSON — all from `ExportBuilder`, all built on the same snapshots the app reads,
so no format can disagree with the UI.

Raw session rows include their project, reusable tags, entry notes, snapshotted
rate and currency, tracked value, and aggregate computer-active/away duration.
Raw distraction rows include their editable text and reusable tags.

The workbook has eight sheets: **Summary**, **Day plan**, **Schedule changes**,
**Sessions**, **Distractions**, **By goal**, **By distraction**, **By day**. Raw
rows come first so nothing is hidden behind a rollup.

CSV quoting follows RFC 4180 — distraction notes are free text and routinely
contain commas, quotes and newlines.

## The xlsx writer

An `.xlsx` is a ZIP of XML parts, so writing real spreadsheets with no third-party
dependency meant writing both. `ZipWriter` stores entries uncompressed (method 0),
which is fully valid ZIP that Excel and Numbers accept — a larger file in exchange
for no dependency to audit and no binary to trust. CRC32 is table-based, and the
DOS timestamp is fixed per archive so identical input produces identical bytes.

`XLSXWriter` uses inline strings rather than a shared-string table (simpler, and
the size difference is irrelevant at focus-log scale) and a five-entry style table
so dates, percentages and two-decimal numbers arrive already formatted rather than
as bare numbers you have to fix by hand.

The parts that actually bite are covered by tests: Excel's 1899-12-30 date epoch,
column letters rolling past Z, sheet names that must be unique and under 31
characters with reserved punctuation stripped, and XML escaping that drops control
characters instead of encoding them. One test writes a real workbook and runs
`unzip -t` over it, which verifies every entry's CRC — the difference between an
archive that is valid and one that is merely labelled correctly.
