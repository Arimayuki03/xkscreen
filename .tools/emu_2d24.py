"""Unicorn 仿真 TempComm 0x2D24（唤醒序列组包器）+ 执行轨迹。
hook 0x3530(cookie)/0x2A68(发送)/0x2BA0(应答)/0x7980(memset)/锁函数。
相对路径以项目根为工作目录：official/TempComm.dll。"""
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
for off, val in ((0x38, 0x8000C00), (0x3C, 0), (0x40, 0x64), (0x44, 0)):
    uc.mem_write(RSP + off, struct.pack("<I", val))
uc.reg_write(unicorn.x86_const.UC_X86_REG_RCX, 0x600000)

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
    if a == 0x3530:  # __security_check_cookie：校验被仿真栈破坏，直接跳过
        ret_now(uc, 0)
    elif a == 0x2A68:  # send(dev, buf, len)
        rdx = uc.reg_read(unicorn.x86_const.UC_X86_REG_RDX)
        r8 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R8) & 0xFFFF
        if 0 < r8 <= 0x1000:
            sent.append(bytes(uc.mem_read(rdx, r8)))
        ret_now(uc, 1)
    elif a == 0x2BA0:  # recv：模拟全 0xFF 成功应答
        r9 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R9)
        r8 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R8) & 0xFFFF
        if 0 < r8 <= 0x1000:
            uc.mem_write(r9, b"\xFF" * r8)
        ret_now(uc, 1)
    elif a == 0x7980:  # memset(rcx, dl, r8)
        rcx = uc.reg_read(unicorn.x86_const.UC_X86_REG_RCX)
        dl = uc.reg_read(unicorn.x86_const.UC_X86_REG_RDX) & 0xFF
        r8 = uc.reg_read(unicorn.x86_const.UC_X86_REG_R8) & 0xFFFF
        if 0 < r8 <= 0x1000:
            uc.mem_write(rcx, bytes([dl]) * r8)
        uc.reg_write(unicorn.x86_const.UC_X86_REG_RAX, rcx)
        ret_now(uc, rcx)
    elif a in (0x2B68, 0x2B18, 0x2B70, 0x297C):  # 锁/清理类：空转
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
    uc.emu_start(IMG + 0x2D24, RET, count=200_000_000)
    print("emu finished")
except unicorn.UcError as e:
    print("err:", e, "rva", hex(uc.reg_read(unicorn.x86_const.UC_X86_REG_RIP) - IMG))

print("last rvas:", [hex(x) for x in last])
print("packets sent:", len(sent))
for i, s in enumerate(sent[:12]):
    print(f"pkt[{i}]:", s.hex(" "))
