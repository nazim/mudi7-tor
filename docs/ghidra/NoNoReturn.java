import ghidra.app.script.GhidraScript;
public class NoNoReturn extends GhidraScript {
    @Override
    public void run() throws Exception {
        setAnalysisOption(currentProgram, "Non-Returning Functions - Discovered", "false");
    }
}
