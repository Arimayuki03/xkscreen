
import ctypes, sys
OUT = r"D:\Code\Xingcan-Xiaolan-Drive\.tools\mem_dump.txt"
log = open(OUT, "a", buffering=1)
def p(*a):
    s=" ".join(str(x) for x in a); log.write(s+"\n")
    try: print(s)
    except: pass
is_adv = ctypes.windll.shell32.IsUserAnAdmin()
p("IsUserAnAdmin:", is_adv)
