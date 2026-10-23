# Ghidra scripts

Used for the findings in `../BINARY-ANALYSIS.md` with Ghidra 12.1.4.

```sh
analyzeHeadless <project dir> glscreen -import /path/to/gl_screen -overwrite \
  -scriptPath docs/ghidra -preScript NoNoReturn.java \
  -postScript DecompContaining.java 0x21c0c0 0x20c75c
```

- `NoNoReturn.java`: pre-script; turns off "Non-Returning Functions -
  Discovered" so task bodies are not cut at the completion callback.
- `DecompContaining.java`: post-script; for each address argument prints the
  containing function and its decompiled C.
