# SQLite for ttt

Browse and query [SQLite](https://sqlite.org) databases inside the [ttt](https://github.com/eugenioenko/ttt) terminal editor.

The plugin drives the `sqlite3` command line shell, so it works with any database file `sqlite3` can open and needs nothing else installed.

## Features

- **Open a database**: `SQLite: Open Database…` takes a path (`~` and relative paths work) and remembers the last ten files under **Recent**. Opening a `.sqlite`, `.sqlite3` or `.db` file from the explorer, or any file that starts with the SQLite header, shows the database overview in that file's tab and makes it the database in the sidebar.
- **Sidebar**: the **SQLite** panel shows the open database, a **Schema** switcher with `main`, `temp` and every attached database, and the tables and views of the selected schema. Tables show their row count on the right, views show `view`. Click a table or press Enter on it to open it in its own editor tab; right-click for **Query**.
- **Table tab**: a **Data** tab with the rows, a page at a time, a `WHERE` filter, and an order by any column, ascending or descending. Press Enter on a row (or double-click it) to see every column of it in full. When the columns don't fit the width, `[` and `]` (or the `‹` `›` buttons) move through them. A **Structure** tab lists the columns (type, not null, default, primary key, generated), indexes, foreign keys, triggers and the `CREATE` statement, which **Open as SQL** opens in a read-only editor tab with highlighting.
- **Query tab**: `SQLite: New Query`, **New Query** in the sidebar, or **Query** on a table opens a tab with an SQL editor. **Run** or F5 runs it and shows the rows, the row count, the rows changed and the time. A script with several `SELECT`s shows one result tab per statement. Errors from `sqlite3` show in red with the line and position it reports, below the results of the statements that ran before it.
- **Attach**: `SQLite: Attach Database…` attaches another file under a schema name, and `SQLite: Detach Schema` removes the selected one. Attachments are remembered per database.

Other commands: `SQLite: Refresh`, `SQLite: Close Database`, `SQLite: Show Panel` and `SQLite: Settings…`. The panel's `⋮` menu has the same entries.

## Reading and writing

Browsing never writes: every file is opened with a `file:` URI and `mode=ro`, so the plugin cannot change a database or create a missing one while you look around.

A query also runs read-only first. When it reaches a statement that writes, `sqlite3` stops with "attempt to write a readonly database" before anything is changed, and the plugin asks whether to run it again with write access (`mode=rw`). Tick **Allow writes** in the query tab to skip the question. After a read-write run, the sidebar and open tables reload.

Each query is a separate `sqlite3` process, so the connection does not outlive it: `temp` tables, `PRAGMA` settings and `ATTACH` statements typed into a query last for that run only. Use **Attach Database…** for attachments that should stay. Every statement runs in autocommit mode unless the script has its own `BEGIN` and `COMMIT`.

## How sqlite3 is called

The plugin runs `sqlite3` with `ttt.system.exec_async` and an argument list, never a shell:

```
sqlite3 -noinit -batch -json [-cmd "ATTACH 'file:…?mode=ro' AS \"name\""]… -cmd ".bail on" "file:/path/to.db?mode=ro"
```

The SQL goes in on standard input. `-noinit` keeps `~/.sqliterc` from changing the output mode (older shells without `-noinit` are retried without it). `.bail on` is turned on with `-cmd` because `-bail` on the command line makes `sqlite3` exit right after the first `-cmd`.

Output is parsed from `-json`, which prints one JSON array per statement that returns rows. It was picked over the other modes because:

- strings are escaped, so values with newlines, tabs, quotes or separator characters can't break the parse, which is the weakness of the `list`, `tabs` and `ascii` modes;
- `NULL` is `null`, distinct from an empty string or the text `NULL`;
- numbers and text are told apart, so numeric columns align right.

The plugin reads the JSON itself instead of with `ttt.json`, to keep the column order and duplicate column names, and to keep integers beyond 2^53 exact. Reals are shown with 15 significant digits in the grid (`sqlite3 -json` prints 17) and exactly in the row view. Blobs show as `<blob N bytes>` in the Data tab; in a query, select `hex(col)` to see one. `-json` prints nothing for a statement without rows, so an empty result has no column names.

## Settings

`SQLite: Settings…` (stored with `ttt.storage`):

- **sqlite3 binary** (`sqlite3_path`, default `sqlite3`): checked with `sqlite3 -version` before it is saved.
- **Page size**: rows per page in tables and query results (25, 50, 100 or 200).
- **Count rows in databases up to (MiB)**: the sidebar counts the rows of every table with `count(*)` when the schema is at most this size (default 64), and leaves the counts out for bigger ones.
- **Query rows kept**: a query keeps at most this many rows per result (default 5000).

ttt runs only the binaries the manifest lists under `system.exec`, matched exactly. The manifest lists `sqlite3` (found on `PATH`) and the usual absolute paths (`/usr/bin`, `/usr/local/bin`, and Homebrew's `/opt/homebrew/bin`, `/opt/homebrew/opt/sqlite/bin` and `/usr/local/opt/sqlite/bin`). To use another path, add it to `plugin.ttt.json` and approve the plugin again, or put that `sqlite3` first on `PATH`.

## Install

Link the repository into ttt's plugins folder and restart ttt:

```sh
ln -s "$PWD/ttt-sqlite" ~/.config/ttt/plugins/sqlite
```

ttt asks you to approve the permissions on first start: `system.exec` (to run `sqlite3`), `system.env` (`HOME` and `PWD`, to expand `~` and relative paths), `editor.file_handlers` (to open database files from the explorer), `storage` (recent files, attachments and settings), `panel.sidebar`, `panel.editor` and `commands`.

## Development

ttt loads a plugin from a single Lua file, so the source lives in `src/` as modules and `scripts/build.py` bundles them into `init.lua`. Edit `src/`, never `init.lua`, and rebuild:

```sh
scripts/build.py           # writes init.lua
scripts/build.py --check   # fails when init.lua is out of date
```

A module's name is its path: `src/features/table/store.lua` is `require("features.table.store")`, and a folder's `init.lua` is the folder itself, so `src/features/table/init.lua` is `require("features.table")`. The bundle runs `src/main.lua`.

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

`Router.show(id, make_page)` opens a page in its own editor tab, or focuses the tab when it is already open. Pages are built from named local functions instead of nested inline closures. Callbacks are wired with `U.bind(fn, ...)`, which passes its bound arguments first and the caller's after them, so functions used as callbacks take their context first and the panel or event arguments last.

Runtime errors point at lines in `init.lua`. Each module starts with a `-- src/…` comment there, so search upward from the line to find the source file.

Format with `stylua src` (settings in `.stylua.toml`).

## Requirements

A `sqlite3` shell with `-json` (SQLite 3.33 or newer). The plugin uses widget features of current ttt: `pager`, `tabs`, table `on_activate`, `selected`, `loading`, `empty` and `inset`, list `badge_right` and `inset`, hstack `align`, button styles, keyvalue `muted_keys`, bordered and titled inputs, and file handlers.

## License

MIT
