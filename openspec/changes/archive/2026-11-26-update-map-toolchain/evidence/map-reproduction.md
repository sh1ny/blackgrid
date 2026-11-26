# Map reproduction

`mise run maps:check` passed with the upgraded dependencies:

```text
Map pack b47e37c71f756146f7e9641a54cdef96303013f5cb6dfcdde058198696b5a78d reproduced byte-identically with xml 7.0.1, image 4.13.1, vector_graphics_compiler 1.3.6, vector_graphics 1.3.1, vector_graphics_codec 1.2.0.
```

The active generation stayed in place. No rebuild or owner artwork check was needed.

`mise run analyze` reported no issues. `mise run test` passed 3,649 application tests and 110 progress package tests. The fast suite includes the existing app-icon rejection cases, the SVG namespace wildcard case and the codec format check. The exact xlink URI assertion runs in hosted qualification.
