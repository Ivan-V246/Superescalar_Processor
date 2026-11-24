# Gera um programa aleatório (prog_aleatorio) e o resultado esperado de x1..x7 (esperado)
# usando um simulador de referência. Uso: python3 gerar_sem_desvio.py <semente> <tamanho>
import random,sys
seed=int(sys.argv[1]); random.seed(seed)
M=0xffffffff
def sx(v,b): v&=(1<<b)-1; return v-(1<<b) if v>>(b-1) else v
regs=[0]*32; mem={}; prog=[]
def R(f7,rs2,rs1,f3,rd): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|0x33
def I(imm,rs1,f3,rd,op=0x13): return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S(imm,rs2,rs1,f3): imm&=0xfff; return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&31)<<7)|0x23
rr=lambda: random.randint(0,7)
for _ in range(int(sys.argv[2])):
    t=random.random()
    if t<0.45:
        op=random.choice(['add','sub','xor','or','and','sll','srl','slt'])
        rd,a,b=random.randint(1,7),rr(),rr(); x,y=regs[a],regs[b]
        f={'add':(0,0,(x+y)&M),'sub':(0x20,0,(x-y)&M),'xor':(0,4,x^y),'or':(0,6,x|y),'and':(0,7,x&y),
           'sll':(0,1,(x<<(y&31))&M),'srl':(0,5,x>>(y&31)),'slt':(0,2,int(sx(x,32)<sx(y,32)))}[op]
        prog.append(R(f[0],b,a,f[1],rd)); regs[rd]=f[2]
    elif t<0.70:
        rd,a,imm=random.randint(1,7),rr(),random.randint(-2048,2047)
        prog.append(I(imm,a,0,rd)); regs[rd]=(regs[a]+imm)&M
    elif t<0.75:   # LUI ou AUIPC (pc = 4 * posição)
        rd=random.randint(1,7); im=random.randint(0,0xfffff)
        if random.random()<0.5:
            prog.append((im<<12)|(rd<<7)|0x37); regs[rd]=(im<<12)&M
        else:
            prog.append((im<<12)|(rd<<7)|0x17); regs[rd]=(4*(len(prog)-1)+(im<<12))&M
    elif t<0.88:
        addr=random.choice([0,4,8,12]); b=rr(); prog.append(S(addr,b,0,2)); mem[addr]=regs[b]
    else:
        addr=random.choice([0,4,8,12]); rd=random.randint(1,7); prog.append(I(addr,0,2,rd,0x03)); regs[rd]=mem.get(addr,0)
    regs[0]=0
open('prog_aleatorio','w').write('\n'.join('%08x'%p for p in prog)+'\n00000073\n')
open('esperado','w').write(' '.join(str(regs[i]) for i in range(1,8)))
