# merge-to-master benchmarks

`bench/bench.luau` times the package through its public API: `merge` over record lists, and
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
  `@tes3` and `@tes3conv`, merged, and the result written as a plugin in memory.

Each workload is warmed up, sized to a batch of about a tenth of a second, and reported as the
median of seven batches, with a full collection between them. Before the batches and after them
its whole result is hashed (every record, reference, summary count, and log line, a record's
fields in the order of their names) and has to come to the hash written in the bench, which is
the baseline's: a merge that does less, or anything else, fails instead of posting a time.

```sh
jess run --package jpk/merge-to-master --package-path jpk \
  --capability filesystem.read --capability filesystem.write \
  jpk/merge-to-master/bench/bench.luau [filter] [scratch folder]
```

Without a scratch folder the command isn't timed, and no capability is needed.

## The move onto l3i 2.0, base against head

- Machine: Intel Core i7-10870H @ 2.20 GHz, 16 threads, shared with other work while this ran.
- Date: 2026-10-12.
- Binary: the verified release build of Jess 0.1.0 on l3i 2.0.1 (Luau 0.742), the same one for
  both sides, with the same `@tes3` and `@tes3conv` beside both.
- Base: `d345af1`, the package before the move, with this bench. Head: `313284e`.
- Protocol: the whole bench run against base, then head, five times over, back to back under one
  lock; each cell is the median of its five runs. A difference under 5 percent is called no
  change.

| Workload | Base | Head | Base / head |
|---|---:|---:|---:|
| a plugin of 2286 records into a master of 16142 | 34.51 ms | 17.60 ms | 1.96x |
| the same, removing the deleted, with the log | 42.15 ms | 26.03 ms | 1.62x |
| objects: 4000 into 24000 | 54.42 ms | 26.84 ms | 2.03x |
| cells: 192 of 96 references into 256 of 128 | 15.80 ms | 10.62 ms | 1.49x |
| cells, removing the deleted: 192 of 96 references into 256 of 128 | 25.71 ms | 15.86 ms | 1.62x |
| landscape textures: 64 and 512 landscapes into 200 and 1024 | 4.574 ms | 3.646 ms | 1.25x |
| dialogue: 500 topics into 800 of 16 INFOs | 16.20 ms | 10.44 ms | 1.55x |
| dialogue after that of another master: 325 topics into 400 of 12 INFOs | 7.695 ms | 6.970 ms | 1.10x |
| commands.merge, a dry run: files of 1086 records into 5792 | 65.47 ms | 62.93 ms | no change |

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
and INFO by INFO, into an empty set to make the same set again: that is the dialogue row, and a
tenth of the rest. A cell's references are found by master and index as one number in a table
that is cleared and reused from cell to cell, where each was a string made by interpolation in a
table made for the cell: the cells rows. `removeDeleted` asks once for each spelling of an id
whether its object was deleted, where it lowered the id of every reference, and searches the
flags only of objects that have any. And a file's cells and textures are listed as they are
collected, so the passes over references and texture indices no longer walk every object to find
them.

What did not move: the command. Reading the two files and writing the merged one is `@tes3`'s and
`@tes3conv`'s work. Timed apart from the command over the same files, `merge` was 12.3 ms of its
72 before and is 6.3 ms of its 67, a sixth then and a tenth now, and the 4 percent the row shows
is under what this machine could tell apart while it was shared. A topic set that another master
leads keeps most of its cost, the INFOs of the target being inserted into the other master's
chains one by one as they were. The texture remap itself is as it was: its time is the base64
both ways and a table read per word, and a buffer in the table's place measured 1.5 µs against
1.9 µs a landscape in a probe, too little of the row to take. An intern pool for the deleted ids
measured slower than the table of spellings that replaced the lowering, and sizing the list of a
cell's renumbered references ahead measured as nothing; neither is in.
