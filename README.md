# SQLite for ttt

Browse and query [SQLite](https://sqlite.org) databases inside the [ttt](https://github.com/eugenioenko/ttt) terminal editor. The plugin drives the `sqlite3` command line shell, so it opens any database file `sqlite3` can open.

## Requirements

- **ttt newer than 1.9.0** (a build of ttt `main` until the next release). The plugin uses cancellable, streamed `sqlite3` runs with timeouts and approval of a custom binary path, which 1.9.0 does not have.
- **sqlite3 3.33 or newer**, the first version with `-json`. Check with `sqlite3 -version`.
  - Ubuntu and Debian: `sudo apt install sqlite3`
  - macOS: `/usr/bin/sqlite3` ships with the system; `brew install sqlite` gives a newer one.

## Install

From ttt: open the **Plugins** tab in the sidebar, search for "sqlite", and click **Install**. Or run **Plugins: Install from URL** with `https://github.com/eugenioenko/ttt-sqlite`.

By hand:

```sh
git clone https://github.com/eugenioenko/ttt-sqlite ~/.config/ttt/plugins/sqlite
```

then restart ttt.

### Permissions

ttt asks you to approve these once, when the plugin is installed:

- `system.exec: sqlite3`: run the `sqlite3` found on your `PATH`. It is the only program the plugin runs, always with an argument list and never through a shell.
- `editor.file_handlers`: open `.db`, `.sqlite` and `.sqlite3` files, and any file with the SQLite header, from the explorer.
- `system.env`: read `HOME` and `PWD`, to expand `~` and relative paths.
- `storage`: remember recent files, attached databases and settings.
- `panel.sidebar`, `panel.editor`, `commands`: the SQLite panel, its tabs and its commands.

To use a `sqlite3` that is not on your `PATH`, set its absolute path in **SQLite: Settings…**. When you save it, ttt asks you once to allow that exact file, and remembers the answer. The plugin asks only for the path you choose instead of listing common install locations in its manifest, so installing it does not grant access to binaries you never use. The file must be named `sqlite3`.

## Use

**Open a database** in any of these ways:

- Open a database file from the explorer: it shows the database overview in that file's tab.
- **SQLite: Open Database…** takes a path (`~` and relative paths work) and lists the last ten files under **Recent**.
- The **SQLite** sidebar panel lists recent files while no database is open.

Opening a database that is already open switches to its tab. **SQLite: Close Database** closes it with every tab it opened.

**Browse** from the sidebar: pick a schema (`main`, `temp` or an attached database), then click a table or view, or press Enter on it, to open it in a tab with its **Data** (paged rows, a `WHERE` filter, ordering) and its **Structure** (columns, indexes, foreign keys, triggers and the `CREATE` statement).

**Query** with **SQLite: New Query**, **New Query** in the sidebar, or **Query** on a table. The cursor starts in the SQL editor.

| Key or button | Does |
|---------------|------|
| F5 or **Run** | Run the SQL. Running again while a query runs stops it and starts over. |
| **Cancel** | Stop the running query. Rows that already arrived stay on screen, marked **Cancelled**. Closing the tab cancels too. |
| Enter or double-click on a row | Show every column of the row. Escape or **Close** closes it. |
| Left and Right, Shift+wheel | Scroll wide results sideways: the arrows jump a column. |
| Tab and Shift+Tab | Move between the editor, buttons and the results. |

A script with several `SELECT`s shows one result tab per statement. Blobs show as `<blob N bytes>` in the Data tab; in a query, select `hex(col)` to see one. Errors from `sqlite3` show in red below the results of the statements that ran before them.

### Reading and writing

Browsing never writes: every file is opened read-only, so the plugin cannot change a database, or create a missing one, while you look around.

A query also runs read-only first. When it reaches a statement that writes, `sqlite3` stops before anything changes, and the plugin asks whether to run the query again with write access. Tick **Allow writes** in the query tab to skip the question. After a run with write access the sidebar and open tables reload.

Each query runs in its own `sqlite3` process, so `temp` tables, `PRAGMA` settings and `ATTACH` statements in a query last for that run only. Use **SQLite: Attach Database…** for attachments that should stay. Statements run in autocommit mode unless the script has its own `BEGIN` and `COMMIT`, so when a query is cancelled or times out, the statements that finished stay committed and the one that was running is rolled back.

### Big results and timeouts

Rows are read as `sqlite3` prints them, so a large result does not have to fit in memory. A query keeps the first **Query rows kept** rows of each result (5000 by default) and says "first 5,000 of 120,000 rows shown". When a query prints more than 64 MiB, the plugin stops `sqlite3` and shows the rows kept so far.

A query that runs longer than the **Query timeout** (5 minutes by default) is stopped and shows **Timed out**. The panel's own lookups (schemas, tables, row counts, structure) stop after 30 seconds.

## Settings

**SQLite: Settings…**:

- **sqlite3 binary**: `sqlite3` (from `PATH`, the default) or an absolute path. It is checked with `sqlite3 -version` before it is saved.
- **Page size**: rows per page in tables and query results (25, 50, 100 or 200).
- **Count rows in databases up to (MiB)**: the sidebar counts the rows of every table when the schema is at most this size (default 64).
- **Query rows kept**: rows kept per query result (default 5000).
- **Query timeout**: 10 seconds to 1 hour, or no timeout (default 5 minutes). It also applies to loading a table's rows, which runs your filter.

## Commands

`SQLite: Open Database…`, `New Query`, `Attach Database…`, `Detach Schema`, `Refresh`, `Close Database`, `Show Panel` and `Settings…`. The sidebar panel's `⋮` menu has the same entries.

## Development

ttt loads a plugin from one Lua file, so the source lives in `src/` as modules and `scripts/build.py` bundles them into `init.lua`. Edit `src/`, never `init.lua`, then:

```sh
scripts/build.py           # writes init.lua
scripts/build.py --check   # fails when init.lua is out of date
stylua src tests           # format (settings in .stylua.toml)
scripts/test.sh            # tests
```

`scripts/test.sh` runs the unit tests in `tests/*_test.lua` with gopher-lua, the Lua that ttt embeds, through the small Go runner in `tests/runner` (needs Go). They cover the `-json` parser, quoting and the `sqlite3` arguments. It then runs `tests/smoke.sh`, which opens a database in the real editor, runs a query and checks that a write is stopped by the read-only first run; it needs `ttt` on `PATH` (or `TTT=/path/to/ttt`) and `sqlite3`, and is skipped without them. CI runs the bundle check, stylua and the tests.

A module's name is its path: `src/features/table/store.lua` is `require("features.table.store")`, and a folder's `init.lua` is the folder itself. The bundle runs `src/main.lua`.

```
src/
  main.lua            registers the sidebar, commands and file handler
  core/               state, sqlite3 runner, JSON result parser, database model, utilities
  components/         forms, dialogs, dropdowns and the result grid
  app/                router, sidebar, open, attach and settings dialogs, paths
  features/table/     a table or view tab: Data and Structure
  features/query/     the query tab
  features/overview/  the database overview a .db file opens in
```

Pages are built from named local functions instead of nested inline closures. Callbacks are wired with `U.bind(fn, ...)`, which passes its bound arguments first and the caller's after them. Runtime errors point at lines in `init.lua`; each module starts with a `-- src/…` comment there.

### How sqlite3 is called

```
sqlite3 -noinit -batch -json [-cmd "ATTACH 'file:…?mode=ro' AS \"name\""]… -cmd ".bail on" "file:/path/to.db?mode=ro"
```

The SQL goes in on standard input. Files are opened by `file:` URI so `sqlite3` never reads a path as a script or creates a file. `-noinit` keeps `~/.sqliterc` from changing the output mode (older shells without it are retried without it). `.bail on` is set with `-cmd` because `-bail` on the command line makes `sqlite3` exit after the first `-cmd`.

Output is `-json`, read with the plugin's own parser (`src/core/results.lua`) as it streams in through `on_stdout`. `-json` escapes strings, keeps `NULL` apart from empty text and the text `NULL`, and tells numbers from text, which `list`, `tabs` and `ascii` do not. It also prints one row per line, so it streams as well as a line-oriented mode: the parser keeps a partial line until the rest arrives, and rows past the cap are counted from their line ends without being decoded. `ttt.json` is not used because it loses the column order and duplicate column names and turns big integers into floats; the parser keeps every value as text. A trailing `SELECT total_changes()` tells a write that changed nothing from one that did.

## License

MIT
