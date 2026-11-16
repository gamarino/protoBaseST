"_timer_table.st: prints PBClusterConfig timerTable as the Markdown table of docs/reference.md
 (a helper of timer_table_sync.sh, never run as a test)."
Import from: 'protobase'.
'| Timer | Default | Drives (liveness only) |' displayNl.
'|---|---|---|' displayNl.
PBClusterConfig timerTable do: [:row |
  ('| ' , (row at: 1) , ' | ' , (row at: 2) , ' | ' , (row at: 3) , ' |') displayNl].
