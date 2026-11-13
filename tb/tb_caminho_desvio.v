module tb_caminho_desvio();

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

caminho_desvio U_cd (
    .clk(clk), .rst(rst),
    .valido(valido), .instr(instr), .pc(pc),
    .valor_rs1(valor_rs1), .valor_rs2(valor_rs2),
    .rob_id(rob_id),
    .previu(previu), .alvo_previsto(alvo_previsto),
    .ready(ready),
    .wb(wb), .rid(rid), .r(r),
    .resolvido(resolvido), .tomado(tomado), .alvo(alvo), .errou(errou)
);

always #5 clk = ~clk;

// Envia uma instrucao, espera a resolucao e confere todas as saidas
task testa;
    input [8*26-1:0] nome;
    input [31:0] _instr;
    input [9:0]  _pc;
    input [31:0] _a, _b;
    input [4:0]  _id;
    input        _previu;
    input [9:0]  _alvo_previsto;
    input [31:0] r_esp;
    input        tomado_esp;
    input [9:0]  alvo_esp;
    input        errou_esp;
    begin
        valido = 1'b1; instr = _instr; pc = _pc;
        valor_rs1 = _a; valor_rs2 = _b; rob_id = _id;
        previu = _previu; alvo_previsto = _alvo_previsto;
        @(posedge clk); #1;
        valido = 1'b0;
        if (wb !== 1'b1 || resolvido !== 1'b1 || rid !== _id || r !== r_esp ||
            tomado !== tomado_esp || alvo !== alvo_esp || errou !== errou_esp) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b resolvido=%b rid=%0d r=%0d tomado=%b alvo=%0d errou=%b",
                     nome, wb, resolvido, rid, r, tomado, alvo, errou);
            $display("          esperado: rid=%0d r=%0d tomado=%b alvo=%0d errou=%b",
                     _id, r_esp, tomado_esp, alvo_esp, errou_esp);
        end else
            $display("  [OK]    %0s: r=%0d tomado=%b alvo=%0d errou=%b", nome, r, tomado, alvo, errou);
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
        $display("  [FALHA] ready=%b alvo=%0d r=%0d", ready, alvo, r);
    end
    testa_vazio("apos reset");

    // r = pc + 4 ; alvo = pc + imm
    $display("--- JAL ---");
    //     nome                instr         pc   rs1           rs2   id     prev ap    r     tom alvo  err
    testa("jal x1, 16",        32'h010000ef, 20,  0,            0,    5'd1,  0,   0,    24,   1,  36,   1);
    testa("jal x1, -20",       32'hfedff0ef, 100, 0,            0,    5'd2,  0,   0,    104,  1,  80,   1);
    testa("jal x0, 8",         32'h0080006f, 0,   0,            0,    5'd3,  0,   0,    4,    1,  8,    1);

    // r = pc + 4 ; alvo = (rs1 + imm) com bit 0 zerado
    $display("--- JALR ---");
    testa("jalr 4(x5) impar",  32'h004280e7, 28,  1001,         0,    5'd4,  0,   0,    32,   1,  1004, 1);
    testa("jalr -8(x5)",       32'hff8280e7, 40,  200,          0,    5'd5,  0,   0,    44,   1,  192,  1);
    testa("jalr 0(x5)",        32'h00028067, 40,  100,          0,    5'd6,  0,   0,    44,   1,  100,  1);

    // r = 0 ; alvo = pc + imm se tomado, senao pc + 4
    $display("--- Desvios: pc = 60 ---");
    testa("beq 25 == 25",      32'h00208463, 60,  25,           25,   5'd7,  0,   0,    0,    1,  68,   1);
    testa("beq 25 == 26",      32'h00208463, 60,  25,           26,   5'd8,  0,   0,    0,    0,  64,   0);
    testa("bne 7 != 10 (-12)", 32'hfe209ae3, 60,  7,            10,   5'd9,  0,   0,    0,    1,  48,   1);
    testa("bne 10 != 10",      32'hfe209ae3, 60,  10,           10,   5'd10, 0,   0,    0,    0,  64,   0);

    // FFFFFFFA = -6 com sinal, 4294967290 sem sinal
    $display("--- Desvios: com sinal x sem sinal, pc = 80, imm = 16 ---");
    testa("blt  -6 < 3",       32'h0020c863, 80,  32'hfffffffa, 3,    5'd11, 0,   0,    0,    1,  96,   1);
    testa("bge  -6 >= 3",      32'h0020d863, 80,  32'hfffffffa, 3,    5'd12, 0,   0,    0,    0,  84,   0);
    testa("bltu grande < 3",   32'h0020e863, 80,  32'hfffffffa, 3,    5'd13, 0,   0,    0,    0,  84,   0);
    testa("bgeu grande >= 3",  32'h0020f863, 80,  32'hfffffffa, 3,    5'd14, 0,   0,    0,    1,  96,   1);
    testa("blt  100 < 100",    32'h0020c863, 80,  100,          100,  5'd15, 0,   0,    0,    0,  84,   0);
    testa("bge  100 >= 100",   32'h0020d863, 80,  100,          100,  5'd16, 0,   0,    0,    1,  96,   1);
    testa("bltu 100 < 100",    32'h0020e863, 80,  100,          100,  5'd17, 0,   0,    0,    0,  84,   0);
    testa("bgeu 100 >= 100",   32'h0020f863, 80,  100,          100,  5'd18, 0,   0,    0,    1,  96,   1);
    testa("desvio funct3 010", 32'h0020a863, 80,  5,            5,    5'd19, 0,   0,    0,    0,  84,   0);
    testa("desvio funct3 011", 32'h0020b863, 80,  5,            5,    5'd20, 0,   0,    0,    0,  84,   0);

    // errou = previsao diferente do que aconteceu
    $display("--- Previsao ---");
    testa("beq tom, prev certa",  32'h00208463, 60,  25,   25,  5'd21, 1,   68,   0,    1,  68,   0);
    testa("beq tom, alvo errado", 32'h00208463, 60,  25,   25,  5'd22, 1,   72,   0,    1,  68,   1);
    testa("beq nao tom, prev tom",32'h00208463, 60,  25,   26,  5'd23, 1,   68,   0,    0,  64,   1);
    testa("beq nao tom, prev nao",32'h00208463, 60,  25,   26,  5'd24, 0,   999,  0,    0,  64,   0);
    testa("jal prev certa",       32'h010000ef, 20,  0,    0,   5'd25, 1,   36,   24,   1,  36,   0);
    testa("jalr alvo sem & ~1",   32'h004280e7, 28,  1001, 0,   5'd26, 1,   1005, 32,   1,  1004, 1);

    // Nao deveriam chegar aqui: respondem sem desviar (sem filtro de tipo)
    $display("--- Fora do escopo ---");
    testa("add",                  32'h002081b3, 80,  5,    5,   5'd27, 0,   0,    0,    0,  84,   0);
    testa("add com previu = 1",   32'h002081b3, 80,  5,    5,   5'd28, 1,   84,   0,    0,  84,   1);

    // pc de 10 bits: pc + imm e pc + 4 dao a volta em 1024
    $display("--- Limite do pc ---");
    testa("jal x1, 8 em 1020",    32'h008000ef, 1020, 0,   0,   5'd29, 0,   0,    1024, 1,  4,    1);
    testa("beq nao tom em 1020",  32'h00208463, 1020, 1,   2,   5'd30, 0,   0,    0,    0,  0,    0);

    $display("--- Sem envio ---");
    @(posedge clk); #1;
    testa_vazio("valido = 0");

    // Um envio por ciclo: cada resolucao sai no ciclo seguinte
    $display("--- Envios seguidos ---");
    previu = 1'b0; alvo_previsto = 10'd0;
    valido = 1'b1; instr = 32'h010000ef; pc = 20; rob_id = 5'd17;                 // jal x1, 16
    @(posedge clk); #1;
    if (wb !== 1'b1 || rid !== 5'd17 || tomado !== 1'b1 || alvo !== 10'd36 || errou !== 1'b1) begin
        erros = erros + 1;
        $display("  [FALHA] envio 1: wb=%b rid=%0d tomado=%b alvo=%0d errou=%b", wb, rid, tomado, alvo, errou);
    end else
        $display("  [OK]    envio 1: rid=17 tomado=1 alvo=36 errou=1");
    instr = 32'h00208463; pc = 60; valor_rs1 = 1; valor_rs2 = 2; rob_id = 5'd18; // beq nao tomado
    @(posedge clk); #1;
    valido = 1'b0;
    if (wb !== 1'b1 || rid !== 5'd18 || tomado !== 1'b0 || alvo !== 10'd64 || errou !== 1'b0) begin
        erros = erros + 1;
        $display("  [FALHA] envio 2: wb=%b rid=%0d tomado=%b alvo=%0d errou=%b", wb, rid, tomado, alvo, errou);
    end else
        $display("  [OK]    envio 2: rid=18 tomado=0 alvo=64 errou=0");
    @(posedge clk); #1;
    testa_vazio("ciclo seguinte");

    $display("--- Reset com envio ---");
    valido = 1'b1; rst = 1'b1; instr = 32'h010000ef; pc = 20; rob_id = 5'd19;
    @(posedge clk); #1;
    valido = 1'b0; rst = 1'b0;
    testa_vazio("reset");
    if (r !== 32'd0 || rid !== 5'd0 || alvo !== 10'd0) begin
        erros = erros + 1;
        $display("  [FALHA] reset: r=%0d rid=%0d alvo=%0d", r, rid, alvo);
    end else
        $display("  [OK]    reset: r=0 rid=0 alvo=0");

    $display("--- Erros: %0d ---", erros);
    $finish;
end

endmodule
