import ghidra.app.script.GhidraScript;
import ghidra.app.decompiler.*;
import ghidra.program.model.listing.Function;
public class DecompContaining extends GhidraScript {
    @Override
    public void run() throws Exception {
        DecompInterface d = new DecompInterface();
        d.openProgram(currentProgram);
        java.util.Set<Function> seen = new java.util.LinkedHashSet<>();
        for (String a : getScriptArgs()) {
            Function f = getFunctionContaining(toAddr(a));
            println("##### " + a + " -> " + (f == null ? "none" : f.getName() + " @" + f.getEntryPoint() + " size=" + f.getBody().getNumAddresses()));
            if (f != null) seen.add(f);
        }
        for (Function f : seen) {
            DecompileResults r = d.decompileFunction(f, 180, monitor);
            println("===== " + f.getName());
            println(r.getDecompiledFunction() == null ? r.getErrorMessage() : r.getDecompiledFunction().getC());
        }
    }
}
