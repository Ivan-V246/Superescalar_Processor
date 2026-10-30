module tb_caminho_desvio();

reg clk, rst;

reg        valido;
reg [31:0] instr;
reg [9:0]  pc;
reg [31:0] valor_rs1, valor_rs2;
reg [4:0]  rob_id;

wire        ready;
wire        wb;
wire [4:0]  rid;
wire [31:0] r;
wire        resolvido, tomado;
wire [9:0]  alvo;

integer erros;

caminho_desvio U_cd (
    .clk(clk), .rst(rst),
    .valido(valido), .instr(instr), .pc(pc),
    .valor_rs1(valor_rs1), .valor_rs2(valor_rs2),
    .rob_id(rob_id), .ready(ready),
    .wb(wb), .rid(rid), .r(r),
    .resolvido(resolvido), .tomado(tomado), .alvo(alvo)
);

always #5 clk = ~clk;

// Envia uma instrucao, espera a resolucao e confere todas as saidas
task testa;
    input [8*24-1:0] nome;
    input [31:0] _instr;
    input [9:0]  _pc;
    input [31:0] _a, _b;
    input [4:0]  _id;
    input [31:0] r_esp;
    input        tomado_esp;
    input [9:0]  alvo_esp;
    begin
        valido = 1'b1; instr = _instr; pc = _pc;
        valor_rs1 = _a; valor_rs2 = _b; rob_id = _id;
        @(posedge clk); #1;
        valido = 1'b0;
        if (wb !== 1'b1 || resolvido !== 1'b1 || rid !== _id || r !== r_esp ||
            tomado !== tomado_esp || alvo !== alvo_esp) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b resolvido=%b rid=%0d r=%0d tomado=%b alvo=%0d",
                     nome, wb, resolvido, rid, r, tomado, alvo);
            $display("          esperado: rid=%0d r=%0d tomado=%b alvo=%0d",
                     _id, r_esp, tomado_esp, alvo_esp);
        end else
            $display("  [OK]    %0s: r=%0d tomado=%b alvo=%0d", nome, r, tomado, alvo);
    end
endtask

// Confere que nada saiu (wb, resolvido e tomado em 0)
task testa_vazio;
    input [8*24-1:0] nome;
    begin
        if (wb !== 1'b0 || resolvido !== 1'b0 || tomado !== 1'b0) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b resolvido=%b tomado=%b", nome, wb, resolvido, tomado);
        end else
            $display("  [OK]    %0s: wb=0 resolvido=0 tomado=0", nome);
    end
endtask

initial begin
    clk = 0; rst = 1; erros = 0;
    valido = 0; instr = 0; pc = 0; valor_rs1 = 0; valor_rs2 = 0; rob_id = 0;

    @(posedge clk); #1;
    rst = 0;

    $display("--- Reset ---");
    if (ready !== 1'b1) begin
        erros = erros + 1;
        $display("  [FALHA] ready=%b", ready);
    end
    testa_vazio("apos reset");

    // r = pc + 4 ; alvo = pc + imm
    $display("--- JAL ---");
    //     nome            instr         pc   rs1    rs2   id     r    tom  alvo
    testa("jal x1, 16",    32'h010000ef, 20,  0,     0,    5'd1,  24,  1,   36);
    testa("jal x1, -20",   32'hfedff0ef, 100, 0,     0,    5'd2,  104, 1,   80);
    testa("jal x0, 8",     32'h0080006f, 0,   0,     0,    5'd3,  4,   1,   8);

    // alvo = (rs1 + imm) com bit 0 zerado
    $display("--- JALR ---");
    testa("jalr 4(x5) impar",  32'h004280e7, 28, 1001, 0,  5'd4,  32,  1,   1004);
    testa("jalr -8(x5)",       32'hff8280e7, 40, 200,  0,  5'd5,  44,  1,   192);

    // r = 0 ; alvo = pc + imm se tomado, senao pc + 4
    $display("--- Desvios: pc = 60 ---");
    testa("beq 25 == 25",      32'h00208463, 60, 25, 25,   5'd6,  0,   1,   68);
    testa("beq 25 == 26",      32'h00208463, 60, 25, 26,   5'd7,  0,   0,   64);
    testa("bne 7 != 10 (-12)", 32'hfe209ae3, 60, 7,  10,   5'd8,  0,   1,   48);
    testa("bne 10 != 10",      32'hfe209ae3, 60, 10, 10,   5'd9,  0,   0,   64);

    // FFFFFFFA = -6 com sinal, 4294967290 sem sinal
    $display("--- Desvios: com sinal x sem sinal, pc = 80, imm = 16 ---");
    testa("blt  -6 < 3",       32'h0020c863, 80, 32'hfffffffa, 3, 5'd10, 0, 1, 96);
    testa("bge  -6 >= 3",      32'h0020d863, 80, 32'hfffffffa, 3, 5'd11, 0, 0, 84);
    testa("bltu grande < 3",   32'h0020e863, 80, 32'hfffffffa, 3, 5'd12, 0, 0, 84);
    testa("bgeu grande >= 3",  32'h0020f863, 80, 32'hfffffffa, 3, 5'd13, 0, 1, 96);
    testa("bgeu 100 >= 100",   32'h0020f863, 80, 100, 100,  5'd14, 0,   1,   96);
    testa("blt  100 < 100",    32'h0020c863, 80, 100, 100,  5'd20, 0,   0,   84);
    testa("bge  100 >= 100",   32'h0020d863, 80, 100, 100,  5'd21, 0,   1,   96);
    testa("bltu 100 < 100",    32'h0020e863, 80, 100, 100,  5'd22, 0,   0,   84);

    // Nao deveriam chegar aqui, mas o ROB nao pode travar: responde sem desviar
    $display("--- Fora do escopo ---");
    testa("add",               32'h002081b3, 80, 5,  5,    5'd15, 0,   0,   84);
    testa("desvio funct3 010", 32'h0020a863, 80, 5,  5,    5'd16, 0,   0,   84);
    testa("desvio funct3 011", 32'h0020b863, 80, 5,  5,    5'd23, 0,   0,   84);

    $display("--- Sem envio ---");
    @(posedge clk); #1;
    testa_vazio("valido = 0");

    // Um envio por ciclo: cada resolucao sai no ciclo seguinte
    $display("--- Envios seguidos ---");
    valido = 1'b1; instr = 32'h010000ef; pc = 20; rob_id = 5'd17;   // jal x1, 16
    @(posedge clk); #1;
    if (wb !== 1'b1 || rid !== 5'd17 || tomado !== 1'b1 || alvo !== 10'd36) begin
        erros = erros + 1;
        $display("  [FALHA] envio 1: wb=%b rid=%0d tomado=%b alvo=%0d", wb, rid, tomado, alvo);
    end else
        $display("  [OK]    envio 1: rid=17 tomado=1 alvo=36");
    instr = 32'h00208463; pc = 60; valor_rs1 = 1; valor_rs2 = 2; rob_id = 5'd18; // beq nao tomado
    @(posedge clk); #1;
    valido = 1'b0;
    if (wb !== 1'b1 || rid !== 5'd18 || tomado !== 1'b0 || alvo !== 10'd64) begin
        erros = erros + 1;
        $display("  [FALHA] envio 2: wb=%b rid=%0d tomado=%b alvo=%0d", wb, rid, tomado, alvo);
    end else
        $display("  [OK]    envio 2: rid=18 tomado=0 alvo=64");
    @(posedge clk); #1;
    testa_vazio("ciclo seguinte");

    $display("--- Reset com envio ---");
    valido = 1'b1; rst = 1'b1; instr = 32'h010000ef; pc = 20; rob_id = 5'd19;
    @(posedge clk); #1;
    valido = 1'b0; rst = 1'b0;
    testa_vazio("reset");

    $display("--- Erros: %0d ---", erros);
    $finish;
end

endmodule
