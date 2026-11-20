module tb_caminho();

reg clk, rst;

reg        valido;
reg [31:0] instr;
reg [9:0]  pc;
reg [31:0] valor_rs1, valor_rs2;
reg [4:0]  rob_id;
reg        previu;
reg [9:0]  alvo_previsto;

wire        ready;
wire        wb;
wire [4:0]  rid;
wire [31:0] r;
wire        resolvido, tomado, errou;
wire [9:0]  alvo;

integer erros;

caminho U_caminho (
    .clk(clk), .rst(rst),
    .valido(valido), .instr(instr),
    .valor_rs1(valor_rs1), .valor_rs2(valor_rs2),
    .rob_id(rob_id), .pc(pc),
    .previu(previu), .alvo_previsto(alvo_previsto),
    .ready(ready),
    .wb(wb), .rid(rid), .r(r),
    .resolvido(resolvido), .tomado(tomado), .alvo(alvo), .errou(errou)
);

always #5 clk = ~clk;

// Envia uma instrucao, espera a resolucao e confere todas as saidas
// confere_r = 0: o r nao e conferido (desvios, onde o valor nao e usado)
task testa;
    input [8*26-1:0] nome;
    input [31:0] _instr;
    input [9:0]  _pc;
    input [31:0] _a, _b;
    input [4:0]  _id;
    input        _previu;
    input [9:0]  _alvo_previsto;
    input        confere_r;
    input [31:0] r_esp;
    input        resolvido_esp, tomado_esp;
    input [9:0]  alvo_esp;
    input        errou_esp;
    begin
        valido = 1'b1; instr = _instr; pc = _pc;
        valor_rs1 = _a; valor_rs2 = _b; rob_id = _id;
        previu = _previu; alvo_previsto = _alvo_previsto;
        @(posedge clk); #1;
        valido = 1'b0;
        if (wb !== 1'b1 || rid !== _id || (confere_r && r !== r_esp) ||
            resolvido !== resolvido_esp || tomado !== tomado_esp ||
            alvo !== alvo_esp || errou !== errou_esp) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b rid=%0d r=%h resolvido=%b tomado=%b alvo=%0d errou=%b",
                     nome, wb, rid, r, resolvido, tomado, alvo, errou);
            $display("          esperado: rid=%0d r=%h resolvido=%b tomado=%b alvo=%0d errou=%b",
                     _id, r_esp, resolvido_esp, tomado_esp, alvo_esp, errou_esp);
        end else
            $display("  [OK]    %0s: r=%h resolvido=%b tomado=%b alvo=%0d errou=%b",
                     nome, r, resolvido, tomado, alvo, errou);
    end
endtask

// Confere que nada saiu
task testa_vazio;
    input [8*26-1:0] nome;
    begin
        if (wb !== 1'b0 || resolvido !== 1'b0 || tomado !== 1'b0 || errou !== 1'b0) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b resolvido=%b tomado=%b errou=%b",
                     nome, wb, resolvido, tomado, errou);
        end else
            $display("  [OK]    %0s: wb=0 resolvido=0 tomado=0 errou=0", nome);
    end
endtask

initial begin
    clk = 0; rst = 1; erros = 0;
    valido = 0; instr = 0; pc = 0; valor_rs1 = 0; valor_rs2 = 0; rob_id = 0;
    previu = 0; alvo_previsto = 0;

    @(posedge clk); #1;
    rst = 0;

    $display("--- Reset ---");
    if (ready !== 1'b1 || alvo !== 10'd0 || r !== 32'd0) begin
        erros = erros + 1;
        $display("  [FALHA] ready=%b alvo=%0d r=%h", ready, alvo, r);
    end
    testa_vazio("apos reset");

    // x3 = x1 op x2 ; nao e salto: alvo = pc + 4
    $display("--- Tipo R ---");
    //     nome              instr         pc  rs1           rs2     id     prev ap  cr r             res tom alvo err
    testa("add",             32'h002081b3, 16, 5,            7,      5'd1,  0,   0,  1, 12,           0,  0,  20,  0);
    testa("sub",             32'h402081b3, 16, 5,            7,      5'd2,  0,   0,  1, 32'hfffffffe, 0,  0,  20,  0);
    testa("xor",             32'h0020c1b3, 16, 6,            3,      5'd3,  0,   0,  1, 5,            0,  0,  20,  0);
    testa("or",              32'h0020e1b3, 16, 6,            3,      5'd4,  0,   0,  1, 7,            0,  0,  20,  0);
    testa("and",             32'h0020f1b3, 16, 6,            3,      5'd5,  0,   0,  1, 2,            0,  0,  20,  0);
    testa("sll",             32'h002091b3, 16, 1,            4,      5'd6,  0,   0,  1, 16,           0,  0,  20,  0);
    testa("sll rs2=33",      32'h002091b3, 16, 1,            33,     5'd7,  0,   0,  1, 2,            0,  0,  20,  0);
    testa("srl",             32'h0020d1b3, 16, 32'h80000000, 4,      5'd8,  0,   0,  1, 32'h08000000, 0,  0,  20,  0);
    testa("sra",             32'h4020d1b3, 16, 32'h80000000, 4,      5'd9,  0,   0,  1, 32'hf8000000, 0,  0,  20,  0);
    testa("slt -1 < 1",      32'h0020a1b3, 16, 32'hffffffff, 1,      5'd10, 0,   0,  1, 1,            0,  0,  20,  0);
    testa("sltu -1 < 1",     32'h0020b1b3, 16, 32'hffffffff, 1,      5'd11, 0,   0,  1, 0,            0,  0,  20,  0);

    // x3 = x1 op imm
    $display("--- Tipo I ---");
    testa("addi 4",          32'h00408193, 16, 10,           0,      5'd12, 0,   0,  1, 14,           0,  0,  20,  0);
    testa("addi -4",         32'hffc08193, 16, 10,           0,      5'd13, 0,   0,  1, 6,            0,  0,  20,  0);
    testa("addi 1030",       32'h40608193, 16, 10,           0,      5'd14, 0,   0,  1, 1040,         0,  0,  20,  0);
    testa("slti 4",          32'h0040a193, 16, 3,            0,      5'd15, 0,   0,  1, 1,            0,  0,  20,  0);
    testa("slti -1",         32'hfff0a193, 16, 0,            0,      5'd16, 0,   0,  1, 0,            0,  0,  20,  0);
    testa("sltiu -1",        32'hfff0b193, 16, 5,            0,      5'd17, 0,   0,  1, 1,            0,  0,  20,  0);
    testa("xori 4",          32'h0040c193, 16, 6,            0,      5'd18, 0,   0,  1, 2,            0,  0,  20,  0);
    testa("ori 4",           32'h0040e193, 16, 3,            0,      5'd19, 0,   0,  1, 7,            0,  0,  20,  0);
    testa("andi 4",          32'h0040f193, 16, 6,            0,      5'd20, 0,   0,  1, 4,            0,  0,  20,  0);
    testa("slli 4",          32'h00409193, 16, 1,            0,      5'd21, 0,   0,  1, 16,           0,  0,  20,  0);
    testa("srli 4",          32'h0040d193, 16, 32'h80000000, 0,      5'd22, 0,   0,  1, 32'h08000000, 0,  0,  20,  0);
    testa("srai 4",          32'h4040d193, 16, 32'h80000000, 0,      5'd23, 0,   0,  1, 32'hf8000000, 0,  0,  20,  0);

    $display("--- LUI / AUIPC ---");
    testa("lui 0x12345",     32'h123451b7, 16, 99,           99,     5'd24, 0,   0,  1, 32'h12345000, 0,  0,  20,  0);
    testa("lui 0xfffff",     32'hfffff1b7, 16, 0,            0,      5'd25, 0,   0,  1, 32'hfffff000, 0,  0,  20,  0);
    testa("auipc 1",         32'h00001197, 16, 0,            0,      5'd26, 0,   0,  1, 32'h00001010, 0,  0,  20,  0);
    testa("auipc 0xfffff",   32'hfffff197, 16, 0,            0,      5'd27, 0,   0,  1, 32'hfffff010, 0,  0,  20,  0);

    // r = endereco rs1 + imm
    $display("--- Load / Store ---");
    testa("lw 16(x1)",       32'h0100a183, 16, 100,          0,      5'd28, 0,   0,  1, 116,          0,  0,  20,  0);
    testa("lw -4(x1)",       32'hffc0a183, 16, 100,          0,      5'd29, 0,   0,  1, 96,           0,  0,  20,  0);
    testa("sw 8(x1)",        32'h0020a423, 16, 100,          55,     5'd30, 0,   0,  1, 108,          0,  0,  20,  0);
    testa("sw -4(x1)",       32'hfe20ae23, 16, 100,          55,     5'd31, 0,   0,  1, 96,           0,  0,  20,  0);

    // r = pc + 4 ; alvo = pc + imm
    $display("--- JAL ---");
    testa("jal x1, 16",      32'h010000ef, 20,  0,           0,      5'd1,  0,   0,  1, 24,           1,  1,  36,  1);
    testa("jal x1, -20",     32'hfedff0ef, 100, 0,           0,      5'd2,  0,   0,  1, 104,          1,  1,  80,  1);
    testa("jal x0, 8",       32'h0080006f, 0,   0,           0,      5'd3,  0,   0,  1, 4,            1,  1,  8,   1);

    // r = pc + 4 ; alvo = (rs1 + imm) com bit 0 zerado
    $display("--- JALR ---");
    testa("jalr 4(x5) impar",32'h004280e7, 28, 1001,         0,      5'd4,  0,   0,  1, 32,           1,  1,  1004, 1);
    testa("jalr -8(x5)",     32'hff8280e7, 40, 200,          0,      5'd5,  0,   0,  1, 44,           1,  1,  192, 1);
    testa("jalr 0(x5)",      32'h00028067, 40, 100,          0,      5'd6,  0,   0,  1, 44,           1,  1,  100, 1);

    // alvo = pc + imm se tomado, senao pc + 4
    $display("--- Desvios: pc = 60 ---");
    testa("beq 25 == 25",    32'h00208463, 60, 25,           25,     5'd7,  0,   0,  0, 0,            1,  1,  68,  1);
    testa("beq 25 == 26",    32'h00208463, 60, 25,           26,     5'd8,  0,   0,  0, 0,            1,  0,  64,  0);
    testa("bne 7 != 10 (-12)",32'hfe209ae3,60, 7,            10,     5'd9,  0,   0,  0, 0,            1,  1,  48,  1);
    testa("bne 10 != 10",    32'hfe209ae3, 60, 10,           10,     5'd10, 0,   0,  0, 0,            1,  0,  64,  0);

    // FFFFFFFA = -6 com sinal, 4294967290 sem sinal
    $display("--- Desvios: com sinal x sem sinal, pc = 80, imm = 16 ---");
    testa("blt  -6 < 3",     32'h0020c863, 80, 32'hfffffffa, 3,      5'd11, 0,   0,  0, 0,            1,  1,  96,  1);
    testa("bge  -6 >= 3",    32'h0020d863, 80, 32'hfffffffa, 3,      5'd12, 0,   0,  0, 0,            1,  0,  84,  0);
    testa("bltu grande < 3", 32'h0020e863, 80, 32'hfffffffa, 3,      5'd13, 0,   0,  0, 0,            1,  0,  84,  0);
    testa("bgeu grande >= 3",32'h0020f863, 80, 32'hfffffffa, 3,      5'd14, 0,   0,  0, 0,            1,  1,  96,  1);
    testa("blt  100 < 100",  32'h0020c863, 80, 100,          100,    5'd15, 0,   0,  0, 0,            1,  0,  84,  0);
    testa("bge  100 >= 100", 32'h0020d863, 80, 100,          100,    5'd16, 0,   0,  0, 0,            1,  1,  96,  1);
    testa("bltu 100 < 100",  32'h0020e863, 80, 100,          100,    5'd17, 0,   0,  0, 0,            1,  0,  84,  0);
    testa("bgeu 100 >= 100", 32'h0020f863, 80, 100,          100,    5'd18, 0,   0,  0, 0,            1,  1,  96,  1);
    testa("desvio funct3 010",32'h0020a863,80, 5,            5,      5'd19, 0,   0,  0, 0,            1,  0,  84,  0);
    testa("desvio funct3 011",32'h0020b863,80, 5,            5,      5'd20, 0,   0,  0, 0,            1,  0,  84,  0);

    // errou = previsao diferente do que aconteceu
    $display("--- Previsao ---");
    testa("beq tom, prev certa",  32'h00208463, 60, 25, 25, 5'd21, 1, 68,  0, 0,  1, 1, 68,  0);
    testa("beq tom, alvo errado", 32'h00208463, 60, 25, 25, 5'd22, 1, 72,  0, 0,  1, 1, 68,  1);
    testa("beq nao tom, prev tom",32'h00208463, 60, 25, 26, 5'd23, 1, 68,  0, 0,  1, 0, 64,  1);
    testa("beq nao tom, prev nao",32'h00208463, 60, 25, 26, 5'd24, 0, 999, 0, 0,  1, 0, 64,  0);
    testa("jal prev certa",       32'h010000ef, 20, 0,  0,  5'd25, 1, 36,  1, 24, 1, 1, 36,  0);
    testa("jalr alvo sem & ~1",   32'h004280e7, 28, 1001, 0, 5'd26, 1, 1005, 1, 32, 1, 1, 1004, 1);
    testa("add com previu = 1",   32'h002081b3, 16, 5,  7,  5'd27, 1, 20,  1, 12, 0, 0, 20,  0);

    // pc de 10 bits: pc + imm e pc + 4 dao a volta em 1024
    $display("--- Limite do pc ---");
    testa("jal x1, 8 em 1020",    32'h008000ef, 1020, 0, 0, 5'd28, 0, 0,   1, 1024, 1, 1, 4,  1);
    testa("beq nao tom em 1020",  32'h00208463, 1020, 1, 2, 5'd29, 0, 0,   0, 0,    1, 0, 0,  0);

    $display("--- Sem envio ---");
    @(posedge clk); #1;
    testa_vazio("valido = 0");

    // Um envio por ciclo: cada resolucao sai no ciclo seguinte
    $display("--- Envios seguidos ---");
    previu = 1'b0; alvo_previsto = 10'd0;
    valido = 1'b1; instr = 32'h010000ef; pc = 20; rob_id = 5'd1;                    // jal x1, 16
    @(posedge clk); #1;
    if (wb !== 1'b1 || rid !== 5'd1 || r !== 32'd24 || resolvido !== 1'b1 || tomado !== 1'b1 ||
        alvo !== 10'd36 || errou !== 1'b1) begin
        erros = erros + 1;
        $display("  [FALHA] envio 1 (jal): wb=%b rid=%0d r=%0d resolvido=%b tomado=%b alvo=%0d errou=%b",
                 wb, rid, r, resolvido, tomado, alvo, errou);
    end else
        $display("  [OK]    envio 1 (jal): rid=1 r=24 tomado=1 alvo=36 errou=1");
    instr = 32'h00408193; pc = 36; valor_rs1 = 1; rob_id = 5'd2;                      // addi x3, x1, 4
    @(posedge clk); #1;
    if (wb !== 1'b1 || rid !== 5'd2 || r !== 32'd5 || resolvido !== 1'b0 || tomado !== 1'b0 ||
        errou !== 1'b0) begin
        erros = erros + 1;
        $display("  [FALHA] envio 2 (addi): wb=%b rid=%0d r=%0d resolvido=%b tomado=%b errou=%b",
                 wb, rid, r, resolvido, tomado, errou);
    end else
        $display("  [OK]    envio 2 (addi): rid=2 r=5 resolvido=0");
    instr = 32'h00208463; pc = 60; valor_rs1 = 1; valor_rs2 = 2; rob_id = 5'd3;      // beq nao tomado
    @(posedge clk); #1;
    valido = 1'b0;
    if (wb !== 1'b1 || rid !== 5'd3 || resolvido !== 1'b1 || tomado !== 1'b0 || alvo !== 10'd64 ||
        errou !== 1'b0) begin
        erros = erros + 1;
        $display("  [FALHA] envio 3 (beq): wb=%b rid=%0d resolvido=%b tomado=%b alvo=%0d errou=%b",
                 wb, rid, resolvido, tomado, alvo, errou);
    end else
        $display("  [OK]    envio 3 (beq): rid=3 tomado=0 alvo=64");
    @(posedge clk); #1;
    testa_vazio("ciclo seguinte");

    $display("--- Reset com envio ---");
    valido = 1'b1; rst = 1'b1; instr = 32'h010000ef; pc = 20; rob_id = 5'd4;
    @(posedge clk); #1;
    valido = 1'b0; rst = 1'b0;
    testa_vazio("reset");
    if (r !== 32'd0 || rid !== 5'd0 || alvo !== 10'd0) begin
        erros = erros + 1;
        $display("  [FALHA] reset: r=%h rid=%0d alvo=%0d", r, rid, alvo);
    end else
        $display("  [OK]    reset: r=0 rid=0 alvo=0");

    $display("--- Erros: %0d ---", erros);
    $finish;
end

endmodule
