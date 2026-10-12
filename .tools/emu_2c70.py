"""Unicorn 仿真 TempComm 0x2C70（唤醒序列发送器）：
cmd 从 0x8000C00 步进 0x400 到 0x8003000，每步 memset 0xFF → xor 混淆 → 0x2A68 发送。
截获全部 64B 唤醒报文。"""
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

RET = 0xDEADBEEF
uc.mem_map(RET & ~0xFFF, 0x1000)
uc.mem_write(RET, b"\xf4")
RSP -= 8
uc.mem_write(RSP, struct.pack("<Q", RET))
uc.reg_write(unicorn.x86_const.UC_X86_REG_RCX, 0x600000)  # dev struct(假)

sent = []
last = []


def ret_now(uc, rax=0):
    rsp = uc.reg_read(unicorn.x86_const.UC_X86_REG_RSP)
    ret = struct.unpack("<Q", uc.mem_read(rsp, 8))[0]
    uc.reg_write(unicorn.x86_const.UC_X86_REG_RSP, rsp + 8)
    uc.reg_write(unicorn.x86_const.UC_X86_REG_RAX, rax)
    uc.reg_write(unicorn.x86_const.UC_X86_REG_RIP, ret)


def hook_code(uc, address, size, ud):
    a = address - IMG
    if len(last) > 16:
        last.pop(0)
    last.append(a)
    if a == 0x3530:  # security cookie
        ret_now(uc, 0)
    elif a == 0x2A68:  # send(dev, buf, len)
        rdx = uc.reg_read(unicorn.x86_const.UC_X86_REG_RDX)
        r8 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R8) & 0xFFFF
        if 0 < r8 <= 0x1000:
            sent.append(bytes(uc.mem_read(rdx, r8)))
        ret_now(uc, 1)
    elif a == 0x2BA0:  # recv: 全 0xFF 应答
        r9 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R9)
        r8 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R8) & 0xFFFF
        if 0 < r8 <= 0x1000:
            uc.mem_write(r9, b"\xFF" * r8)
        ret_now(uc, 1)
    elif a == 0x7980:  # memset
        rcx = uc.reg_read(unicorn.x86_const.UC_X86_REG_RCX)
        dl = uc.reg_read(unicorn.x86_const.UC_X86_REG_RDX) & 0xFF
        r8 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R8) & 0xFFFF
        if 0 < r8 <= 0x1000:
            uc.mem_write(rcx, bytes([dl]) * r8)
        uc.reg_write(unicorn.x86_const.UC_X86_REG_RAX, rcx)
        ret_now(uc, rcx)
    elif a in (0x2B68, 0x2B18, 0x2B70, 0x297C):
        ret_now(uc, 0)


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
    uc.emu_start(IMG + 0x2C70, RET, count=50_000_000)
    print("emu finished")
except unicorn.UcError as e:
    print("err:", e, "rva", hex(uc.reg_read(unicorn.x86_const.UC_X86_REG_RIP) - IMG))

print("packets sent:", len(sent))
for i, s in enumerate(sent[:10]):
    print(f"pkt[{i}]:", s.hex(" "))
