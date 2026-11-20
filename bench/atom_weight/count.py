# gdb script (bench/run_atom_weight.sh): counts protoCore's cell allocations
# (proto::Cell::operator new) between the probe's markers, the calls
# `Smalltalk getenv: 'AW_ON:<label>'` and `Smalltalk getenv: 'AW_OFF'`, and prints
# 'AWCOUNT <label> cells=<count>' at each AW_OFF.
import gdb
gdb.execute("set pagination off")
state = {"on": False, "label": None, "n": 0}
def read_std_string(addr):
    inf = gdb.selected_inferior()
    ptr = int.from_bytes(bytes(inf.read_memory(addr, 8)), 'little')
    ln = int.from_bytes(bytes(inf.read_memory(addr + 8, 8)), 'little')
    if ln > 200: return ""
    return bytes(inf.read_memory(ptr, ln)).decode('utf-8', 'replace')
class Alloc(gdb.Breakpoint):
    def stop(self):
        if state["on"]: state["n"] += 1
        return False
class Marker(gdb.Breakpoint):
    def stop(self):
        s = read_std_string(int(gdb.parse_and_eval("$rsi")))
        if s.startswith("AW_ON:"):
            state.update(on=True, label=s[6:], n=0); ALLOC.enabled = True
        elif s == "AW_OFF":
            print("AWCOUNT %s cells=%d" % (state["label"], state["n"]), flush=True)
            state["on"] = False; ALLOC.enabled = False
        return False
gdb.execute("set debuginfod enabled off")
gdb.execute("start", to_string=True)
Marker("protoio::process::getenv", internal=True)
ALLOC = Alloc("_ZN5proto4CellnwEmPNS_12ProtoContextE", internal=True)
ALLOC.enabled = False
gdb.execute("continue")
