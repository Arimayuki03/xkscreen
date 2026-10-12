"""Unicorn 仿真 TempComm 0x2D24：截获全部数据报文（stdout 打印，不落盘）。
协议确认：[0]=0x34，[5..8]=cmd 小端，其余为 LFSR 混淆。"""
import struct
import unicorn
import pefile

pe = pefile.PE("official/TempComm.dll")
IMG = 0x180000000

uc = unicorn.Uc(unicorn.UC_ARCH_X86, unicorn.UC_MODE_64)
uc.mem_map(IMG, 0x30000)
uc.mem_write(IMG, pe.header)
for s in pe.sections:
    data = s.get_data()
    if data:
        uc.mem_write(IMG + s.VirtualAddress, data)

STACK = 0x7FF000000000
uc.mem_map(STACK, 0x100000)
RSP = STACK + 0x80000
uc.reg_write(unicorn.x86_const.UC_X86_REG_RSP, RSP)
uc.mem_map(0x500000, 0x100000)
uc.mem_map(0x900000, 0x100000)

RET = 0xDEADBEEF
uc.mem_map(RET & ~0xFFF, 0x1000)
uc.mem_write(RET, b"\xf4")
RSP -= 8
uc.mem_write(RSP, struct.pack("<Q", RET))
for off, val in ((0x38, 0x8000C00), (0x3C, 0), (0x40, 0x64), (0x44, 0)):
    uc.mem_write(RSP + off, struct.pack("<I", val))
uc.reg_write(unicorn.x86_const.UC_X86_REG_RCX, 0x600000)

sent = []
nc = {"a68": 0, "b18": 0}


def safe_zero(uc, addr, n):
    for off in range(0, n, 0x1000):
        page = (addr + off) & ~0xFFF
        try:
            uc.mem_map(page, 0x1000)
        except Exception:
            pass
    uc.mem_write(addr, bytes(n))


def ret_now(uc, rax=0):
    rsp = uc.reg_read(unicorn.x86_const.UC_X86_REG_RSP)
    ret = struct.unpack("<Q", uc.mem_read(rsp, 8))[0]
    uc.reg_write(unicorn.x86_const.UC_X86_REG_RSP, rsp + 8)
    uc.reg_write(unicorn.x86_const.UC_X86_REG_RAX, rax)
    uc.reg_write(unicorn.x86_const.UC_X86_REG_RIP, ret)


def hook_code(uc, address, size, ud):
    a = address - IMG
    if a == 0x3530:  # security cookie
        ret_now(uc, 0)
    elif a == 0x2A68:  # send+recv 同缓冲
        nc["a68"] += 1
        rdx = uc.reg_read(unicorn.x86_const.UC_X86_REG_RDX)
        sent.append(bytes(uc.mem_read(rdx, 64)))
        safe_zero(uc, rdx, 64)
        ret_now(uc, 1)
    elif a == 0x2B18:  # 读应答到 rcx
        nc["b18"] += 1
        rcx = uc.reg_read(unicorn.x86_const.UC_X86_REG_RCX)
        safe_zero(uc, rcx, 64)
        ret_now(uc, 0)
    elif a == 0x7980:  # memset
        rcx = uc.reg_read(unicorn.x86_const.UC_X86_REG_RCX)
        dl = uc.reg_read(unicorn.x86_const.UC_X86_REG_RDX) & 0xFF
        r8 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R8) & 0xFFFF
        if 0 < r8 <= 0x1000:
            uc.mem_write(rcx, bytes([dl]) * r8)
        uc.reg_write(unicorn.x86_const.UC_X86_REG_RAX, rcx)
        ret_now(uc, rcx)


uc.hook_add(unicorn.UC_HOOK_CODE, hook_code)


def hmem(uc, access, address, size, value, ud):
    page = address & ~0xFFF
    try:
        uc.mem_map(page, 0x1000)
    except Exception:
        pass
    return True


uc.hook_add(
    unicorn.UC_HOOK_MEM_READ_UNMAPPED | unicorn.UC_HOOK_MEM_WRITE_UNMAPPED,
    hmem,
)

try:
    uc.emu_start(IMG + 0x2D24, RET, count=400_000_000)
    print("finished")
except unicorn.UcError as e:
    print("err:", e)

print("calls:", nc, "packets:", len(sent))
for i, s in enumerate(sent):
    print(f"pkt[{i}]: {s.hex()}")
