# merge-to-master benchmarks

`bench/bench.jsl` times the package through its public API: `merge` over record lists, and
`commands.merge` over plugin files. The lists are made by the bench, the same every run: a master
and the plugin made on it, with objects of 23 types under ids of two words and a number, cells of
references, path grids, landscape textures and landscapes whose texture indices are tes3conv's
base64 (one in sixteen as rows of numbers), and topics with their chains of INFOs. The plugin
has its own of some of the master's objects (spelled in capitals), new ones, cells over the
master's that by turns move one of its references and place one of their own, textures the master
has under another index, and INFOs put into the master's chains in each way an INFO can be.

- *a plugin of 2286 records into a master of 16142* is all of that at once, 28,032 references
  between the two; *the same, removing the deleted, with the log* is `--remove-deleted` over it
  with a log list, as the command line calls `merge`, the plugin deleting 200 objects.
- The others are a master and a plugin of mostly one thing, to show each part of a merge by
  itself: objects alone, cells and their 53,504 references (once more with `removeDeleted`, 128
  placed objects deleted), textures and landscapes, topics, and topics when another master of the
  plugin's has some of them too.
- *commands.merge, a dry run* writes a plugin of 1,086 records and a master of 5,792 (184 KB and
  808 KB) into the scratch folder once, and times the command over the files: both read through
  `@esm` and `@tes3conv`, merged, and the result written as a plugin in memory.

Each workload is warmed up, sized to a batch of about a tenth of a second, and reported as the
median of seven batches, with a full collection between them. Before the batches and after them
its whole result is hashed (every record, reference, summary count, and log line, a record's
fields in the order of their names) and has to come to the hash written in the bench, which is
the baseline's: a merge that does less, or anything else, fails instead of posting a time.

```sh
jess run --package jpk/merge-to-master --package-path jpk \
  --capability filesystem.read --capability filesystem.write \
  jpk/merge-to-master/bench/bench.jsl [filter] [scratch folder]
```

Without a scratch folder the command isn't timed, and no capability is needed.

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran.
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.1 (Luau 0.742), the same one for
  both sides, with the same `@esm` and `@tes3conv` beside both.
- Base: `d345af1`, the package before the move, with this bench. Head: `3b8741a`, the move and
  the one fix after it, which costs nothing.
- Protocol: the whole bench run against base, then head, seven times over, back to back under one
  lock; each cell is the median of its seven runs. A difference under 5 percent is called no
  change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| a plugin of 2286 records into a master of 16142 | 35.83 ms | 17.75 ms | 2.02x |
| the same, removing the deleted, with the log | 43.82 ms | 25.90 ms | 1.69x |
| objects: 4000 into 24000 | 61.57 ms | 26.37 ms | 2.34x |
| cells: 192 of 96 references into 256 of 128 | 15.89 ms | 10.34 ms | 1.54x |
| cells, removing the deleted: 192 of 96 references into 256 of 128 | 25.66 ms | 16.21 ms | 1.58x |
| landscape textures: 64 and 512 landscapes into 200 and 1024 | 4.753 ms | 3.533 ms | 1.35x |
| dialogue: 500 topics into 800 of 16 INFOs | 16.00 ms | 10.75 ms | 1.49x |
| dialogue after that of another master: 325 topics into 400 of 12 INFOs | 7.633 ms | 6.521 ms | 1.17x |
| commands.merge, a dry run: files of 1086 records into 5792 | 68.52 ms | 62.72 ms | 1.09x |

This table is the second measurement of the move, made by its review, and it replaces the first.
The first, the same seven rounds on `9caaa78`, gave 1.97x, 1.58x, 2.47x, 1.52x, 1.56x, 1.38x,
1.65x, 1.39x, and 1.14x down the same rows: within a tenth of these but for the two dialogue
rows. The topics after another master's are 1.2x, not 1.4x: their base read 8.889 ms in that run
and has read 7.1 to 8.5 ms in every run since, the two dialogue rows alone, nine rounds, gave
1.56x and 1.26x, and the two runs of five rounds before the first table gave 1.55x and 1.53x for
the one and 1.10x and 1.20x for the other. The same nine rounds put `9caaa78` beside the head and
found them the same, 10.34 ms against 10.08 ms and 6.07 ms against 6.14 ms.

Each change made for speed, timed alone: its parent against it, five rounds, on the row it is in.

| Change | Row | Parent | Change | Parent / change |
|---|---|---:|---:|---:|
| `1dca43c`, the objects ordered by `argsort` | objects | 58.07 ms | 33.00 ms | 1.76x |
| `902fce3`, a reference's master and index as one number | cells | 15.27 ms | 11.87 ms | 1.29x |
| `fe1094c`, one index of references for every cell | cells | 11.83 ms | 10.10 ms | 1.17x |
| `524dfe5`, the first master as it was collected | dialogue | 15.77 ms | 10.99 ms | 1.44x |
| | dialogue after another master's | 7.762 ms | 6.959 ms | 1.12x |
| `9f4a393`, each spelling of an id asked after once | cells, removing the deleted | 20.36 ms | 16.13 ms | 1.26x |
| `0e2a015`, nothing walked for what to ignore | the whole merge | 18.34 ms | 17.89 ms | 1.03x, no change |
| | objects | 25.89 ms | 25.15 ms | 1.03x, no change |
| `1522b99`, a file's cells and textures listed | the whole merge | 17.74 ms | 16.95 ms | 1.05x |
| | the same, removing the deleted | 26.41 ms | 25.05 ms | 1.05x |
| | landscape textures | 3.688 ms | 3.608 ms | 1.02x, no change |
| `adf3fa4`, an object without flags passed over | the same, removing the deleted | 26.17 ms | 25.11 ms | 1.04x, no change |
| | cells, removing the deleted | 15.51 ms | 15.10 ms | 1.03x, no change |
| `9caaa78`, a topic the target lacks handed over | dialogue | 10.73 ms | 10.79 ms | 0.99x, no change |
| | dialogue after another master's | 6.969 ms | 6.378 ms | 1.09x |

The first five carry the move, and `9caaa78` a tenth of one row. `0e2a015` and `adf3fa4` each
read three or four percent faster on every row tried, which is under what this machine can tell
from nothing, and `1522b99` is at the edge of it; none reads slower, so they stay, but they are
not where the time went. `c1e6b64` is not in the table: `313284e` took it back.

What moved, and why. Almost none of it is the dialect's syntax: the `all` over a range, the
record patterns, and the comprehensions the suites took are in code that runs once a merge or
once a test, and measure as nothing. The one place the dialect is in the hot path is the last
line of the ordering, a comprehension over a typed slice of `argsort`'s output. Half of a merge of
objects was `table.sort` calling a comparator over a table per object: each object's place is now
one f64 (its type's place, its sort hint, where its id falls among the ids sorted as strings, and
a path grid after its cell), and the f64s are sorted by one stable `@dream/data` `argsort`; an
object whose hint isn't a small whole number sends them all to the comparator, as before. That is
most of the objects row, and what is left of the ordering is the sort of the ids themselves and
the table that ranks them. The first master a merge reads is no longer merged, record by record
and INFO by INFO, into an empty set to make the same set again, and a topic the target lacks is
handed over as it is where its chain was copied node by node: those two are the dialogue rows,
and a tenth of the rest. A cell's references are found by master and index as one number in a
table that is cleared and reused from cell to cell, where each was a string made by interpolation
in a table made for the cell: the cells rows. `removeDeleted` asks once for each spelling of an id
whether its object was deleted, where it lowered the id of every reference, and searches the
flags only of objects that have any. And a file's cells and textures are listed as they are
collected, so the passes over references and texture indices no longer walk every object to find
them.

What moved least: the command. Reading the two files and writing the merged one is `@esm`'s and
`@tes3conv`'s work. Timed apart from the command over the same files, `merge` was 12.3 ms of its
72 before and is 6.3 ms of its 67, a sixth then and a tenth now: under a tenth is what the row
can have gained, and the 1.09x of this run is that. The texture remap itself is
as it was: its time is the base64 both ways and a table read per word, and a buffer in the
table's place measured 1.5 µs against 1.9 µs a landscape in a probe, too little of the row to
take; the row's gain is the ordering and the walks around it. An intern pool for the deleted ids
measured slower than the table of spellings that replaced the lowering, and sizing the list of a
cell's renumbered references ahead measured as nothing; neither is in. Keeping the objects of the
families that share their ids under the bare id, without a prefix joined to it, was worth a
twentieth of the objects row and was taken back: the keys order the walk that finds the highest
texture of a master whose indices aren't all numbers, and that order is the baseline's to keep.

## Which modules are native, and why

Jess compiles to machine code only what is marked (`--!native` on a module, `@native` on one
function), and every load pays for what is marked. A module carries `--!native` when a row below
spends its time there and the module is small (12 KB or less); a larger module carries `@native`
on the functions the row spends its time in, and nothing else.

Measured 2026-10-15 with `jess 0.1.0`, the verified release build of jess `07c38cb` on l3i
2.0.3, on the i7-10870H, the one-minute load 1.32 and 1.27 at the start of the two
sessions. In each session the bench ran alternately on this package and on a copy of it with
every module marked, three fresh runs of `bench/bench.jsl` each, every run's row the median of
its batches; a column is the median of the three, and a ratio is against the all-marked runs of
the same session. Which functions a row spends its time in comes from `jess run --profile` of
that row alone, unmarked. The load cost is a fresh `jess run --package <this package>
--package-path jpk` of a script that only requires `@merge-to-master`, the two sides alternating, the
median of five each after one warm-up.

| Requiring `@merge-to-master` | All marked | This state |
| --- | ---: | ---: |
| Unmarked | 0.054 s | 0.049 s |
| Final | 0.054 s | 0.051 s |

| Row | All marked (ms) | Unmarked / all marked | Final (ms) | Final / all marked |
| --- | ---: | ---: | ---: | ---: |
| a plugin of 2286 records into a master of 16142 | 16.95 | **1.663×** | 17.40 | 1.027× |
| the same, removing the deleted, with the log | 24.40 | **1.585×** | 24.96 | 1.023× |
| objects: 4000 into 24000 | 24.88 | **1.589×** | 25.08 | 1.008× |
| cells: 192 of 96 references into 256 of 128 | 10.09 | **1.800×** | 9.873 | 0.978× |
| cells, removing the deleted: 192 of 96 references into 256 of 128 | 15.01 | **1.774×** | 15.21 | 1.014× |
| landscape textures: 64 and 512 landscapes into 200 and 1024 | 3.252 | **1.994×** | 3.341 | 1.027× |
| dialogue: 500 topics into 800 of 16 INFOs | 10.07 | **1.391×** | 9.991 | 0.992× |
| dialogue after that of another master: 325 topics into 400 of 12 INFOs | 5.907 | **1.514×** | 6.165 | 1.044× |
| commands.merge, a dry run: files of 1086 records into 5792 | 69.76 | 1.050× | 68.51 | 0.982× |

What carries the directive (every function here is one a row spends its time in, unmarked):

- `init`, by function: `objectKey`, `insertAfter`, `insertInfo`, `repairLinks`, `collect`,
  `packedIndices`, `mergeReferences`, `nextReferenceIndex`, `remapMasters`, `remapIndices`,
  `removeIgnored`, `removeDeleted`, `placing`, `orderedObjects`, `intoRecords`.
- Unmarked: `cli`, `commands`, `main`.

These are the merge itself: placing objects and dialogue, remapping masters and references,
repairing INFO links. Unmarked, eight of the nine rows ran more than 5% slower; with these marked,
none is, and requiring `@merge-to-master` costs 3 ms less than all marked.
