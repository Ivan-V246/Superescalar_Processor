# Gera um programa aleatório (prog_aleatorio) e o resultado esperado de x1..x9 (esperado)
# usando um simulador de referência. Uso: python3 gerar_com_desvio.py <semente> <tamanho>
import random,sys
seed=int(sys.argv[1]); random.seed(seed)
M=0xffffffff
def sx(v,b): v&=(1<<b)-1; return v-(1<<b) if v>>(b-1) else v
def R(f7,rs2,rs1,f3,rd): return (f7<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|0x33
def I(imm,rs1,f3,rd,op=0x13): return ((imm&0xfff)<<20)|(rs1<<15)|(f3<<12)|(rd<<7)|op
def S(imm,rs2,rs1,f3): imm&=0xfff; return ((imm>>5)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|((imm&31)<<7)|0x23
def B(imm,rs2,rs1,f3):
    imm&=0x1fff
    return (((imm>>12)&1)<<31)|(((imm>>5)&0x3f)<<25)|(rs2<<20)|(rs1<<15)|(f3<<12)|(((imm>>1)&0xf)<<8)|(((imm>>11)&1)<<7)|0x63
def J(imm,rd):
    imm&=0x1fffff
    return (((imm>>20)&1)<<31)|(((imm>>1)&0x3ff)<<21)|(((imm>>11)&1)<<20)|(((imm>>12)&0xff)<<12)|(rd<<7)|0x6f
def JALR(imm,rs1,rd): return I(imm,rs1,0,rd,0x67)
prog=[]
rr=lambda: random.randint(0,7)
def reto():
    t=random.random()
    if t<0.45:
        f7,f3=random.choice([(0,0),(0x20,0),(0,4),(0,6),(0,7),(0,1),(0,5),(0,2),(0,3),(0x20,5)])
        prog.append(R(f7,rr(),rr(),f3,random.randint(1,7)))
    elif t<0.75: prog.append(I(random.randint(-2048,2047),rr(),0,random.randint(1,7)))
    elif t<0.88: prog.append(S(random.choice([0,4,8,12]),rr(),0,2))
    else: prog.append(I(random.choice([0,4,8,12]),0,2,random.randint(1,7),0x03))
N=int(sys.argv[2])
while len(prog)<N:
    t=random.random()
    if t<0.55: reto()
    elif t<0.75:   # desvio para frente
        k=random.randint(1,4); f3=random.choice([0,1,4,5,6,7])
        prog.append(B(4*(k+1),rr(),rr(),f3))
        for _ in range(k): reto()
    elif t<0.85:   # laço com contador x8
        n=random.randint(1,4); body=random.randint(1,4)
        prog.append(I(n,0,0,8))
        ini=len(prog)
        for _ in range(body): reto()
        prog.append(I(-1,8,0,8))
        prog.append(B(4*(ini-len(prog)),0,8,1))   # bne x8, x0, ini
    elif t<0.93:   # jal para frente
        k=random.randint(1,3); prog.append(J(4*(k+1),random.choice([0,1,2,3])))
        for _ in range(k): reto()
    else:          # jalr: x9 = endereço seguinte; salta para frente
        prog.append(J(4,9))
        base=len(prog)
        m=random.randint(0,2)
        for _ in range(m): reto()
        k=random.randint(1,3)
        alvo=len(prog)+1+k
        prog.append(JALR(4*(alvo-base),9,random.choice([0,1,2])))
        for _ in range(k): reto()
prog.append(0x00000073)
# simulador de referência
regs=[0]*32; mem={}; pc=0; passos=0
while True:
    passos+=1
    if passos>20000: raise SystemExit("laco infinito")
    ins=prog[pc//4]; op=ins&0x7f; rd=(ins>>7)&31; f3=(ins>>12)&7; a=regs[(ins>>15)&31]; b=regs[(ins>>20)&31]; f7=ins>>25
    npc=pc+4
    if ins==0x73: break
    if op==0x33:
        v={0:(a-b if f7 else a+b),1:a<<(b&31),2:int(sx(a,32)<sx(b,32)),3:int(a<b),4:a^b,5:(sx(a,32)>>(b&31) if f7 else a>>(b&31)),6:a|b,7:a&b}[f3]
        regs[rd]=v&M
    elif op==0x13: regs[rd]=(a+sx(ins>>20,12))&M
    elif op==0x03: regs[rd]=mem.get((a+sx(ins>>20,12))&M,0)
    elif op==0x23: mem[(a+sx(((ins>>25)<<5)|((ins>>7)&31),12))&M]=b
    elif op==0x63:
        imm=sx((((ins>>31)&1)<<12)|(((ins>>7)&1)<<11)|(((ins>>25)&0x3f)<<5)|(((ins>>8)&0xf)<<1),13)
        c={0:a==b,1:a!=b,4:sx(a,32)<sx(b,32),5:sx(a,32)>=sx(b,32),6:a<b,7:a>=b}[f3]
        if c: npc=pc+imm
    elif op==0x6f:
        imm=sx((((ins>>31)&1)<<20)|(((ins>>12)&0xff)<<12)|(((ins>>20)&1)<<11)|(((ins>>21)&0x3ff)<<1),21)
        regs[rd]=(pc+4)&M; npc=pc+imm
    elif op==0x67:
        t=(a+sx(ins>>20,12))&~1; regs[rd]=(pc+4)&M; npc=t
    regs[0]=0; pc=npc
assert len(prog)<=250, len(prog)
open('prog_aleatorio','w').write('\n'.join('%08x'%p for p in prog)+'\n')
open('esperado','w').write(' '.join(str(regs[i]) for i in range(1,10)))
print(passos)
