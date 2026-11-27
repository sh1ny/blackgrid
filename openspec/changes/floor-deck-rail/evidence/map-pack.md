# Floor-order rebuild

`mise run maps:rebuild -- --reviewed-floor-order` replaced `b47e37c71f756146f7e9641a54cdef96303013f5cb6dfcdde058198696b5a78d` with `61e9616110fc14be4f9381a2270bdcb8f7b0229fbec9faaff91e25ba2ac4c2d8`.

| Map | Prepared floors, bottom to top |
| --- | --- |
| Factory | Basement → Ground_Floor → Second_Floor → Third_Floor |
| Customs | Underground_Level → Ground_Level → Second_Floor → Third_Floor → Fourth_Floor |
| Shoreline | Underground_Level → Ground_Level → Second_Floor → Third_Floor |
| Labs | Technical_Level → First_Level → Second_Level |
| Reserve | Bunkers → Ground_Level → Second_Floor → Third_Floor → Fourth_Floor → Fifth_Floor |
| Streets of Tarkov | Underground_Level → Ground_Level → Second_Floor → Third_Floor → Fourth_Floor → Fifth_Floor |
| Ground Zero | Underground_Level → Ground_Level → Second_Floor → Third_Floor |

Both manifests list the same 1,321 output paths. Only `evidence/calibration.json` and `evidence/sources.json` changed hashes. No artwork, marker or label files changed. The Labs raster overlays still paint Second Level before Technical Level.

`mise run maps:check`:

```text
Map pack 61e9616110fc14be4f9381a2270bdcb8f7b0229fbec9faaff91e25ba2ac4c2d8 reproduced byte-identically with xml 7.0.1, image 4.13.1, vector_graphics_compiler 1.3.6, vector_graphics 1.3.1, vector_graphics_codec 1.2.0.
```

The owner's offline app check is pending.
