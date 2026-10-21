+++
title = "merge-to-master"
description = "Merges a plugin's objects and topics into its master, deleted records removed, as a Jess command in Luau."
date = 2026-10-21

[taxonomies]
tags = ["Jess", "Luau", "OpenMW"]

[extra]
sections = ["overview", "releases", "credits"]
+++

Merges a plugin's objects and topics into its master, deleted records removed, as a Jess command in Luau.

<!-- more -->

A [Jess](https://github.com/DreamWeave-MP/jess) package, `org.dreamweave.merge-to-master`. Add it to a `jess.toml` and
`jess workspace sync` pins it from this site:

```toml
[dependencies]
"org.dreamweave.merge-to-master" = "0.1"
```

Every release below is the package's own archive, with its content digest beside the archive's
SHA-256; `jess.lock` pins the first and checks both.
