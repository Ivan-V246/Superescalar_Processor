module tb_caminho();

//IVAN FEATURE: O caminho comum não resolve mais desvios (são do caminho_desvio).
//As portas previu, alvo_previsto, resolvido, tomado, alvo e errou saíram, e os
//testes de JAL, JALR, condicionais e previsão estão no tb_caminho_desvio.

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

integer erros;

caminho U_caminho (
    .clk(clk), .rst(rst),
    .valido(valido), .instr(instr),
    .valor_rs1(valor_rs1), .valor_rs2(valor_rs2),
    .rob_id(rob_id), .pc(pc),
    .ready(ready),
    .wb(wb), .rid(rid), .r(r)
);

always #5 clk = ~clk;

// Envia uma instrucao, espera o resultado e confere wb, rid e r
task testa;
    input [8*26-1:0] nome;
    input [31:0] _instr;
    input [9:0]  _pc;
    input [31:0] _a, _b;
    input [4:0]  _id;
    input [31:0] r_esp;
    begin
        valido = 1'b1; instr = _instr; pc = _pc;
        valor_rs1 = _a; valor_rs2 = _b; rob_id = _id;
        @(posedge clk); #1;
        valido = 1'b0;
        if (wb !== 1'b1 || rid !== _id || r !== r_esp) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b rid=%0d r=%h", nome, wb, rid, r);
            $display("          esperado: rid=%0d r=%h", _id, r_esp);
        end else
            $display("  [OK]    %0s: r=%h", nome, r);
    end
endtask

// Confere que nada saiu
task testa_vazio;
    input [8*26-1:0] nome;
    begin
        if (wb !== 1'b0) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b", nome, wb);
        end else
            $display("  [OK]    %0s: wb=0", nome);
    end
endtask

initial begin
    clk = 0; rst = 1; erros = 0;
    valido = 0; instr = 0; pc = 0; valor_rs1 = 0; valor_rs2 = 0; rob_id = 0;

    @(posedge clk); #1;
    rst = 0;

    $display("--- Reset ---");
    if (ready !== 1'b1 || r !== 32'd0) begin
        erros = erros + 1;
        $display("  [FALHA] ready=%b r=%h", ready, r);
    end
    testa_vazio("apos reset");

    // x3 = x1 op x2
    $display("--- Tipo R ---");
    //     nome              instr         pc  rs1           rs2     id     r
    testa("add",             32'h002081b3, 16, 5,            7,      5'd1,  12);
    testa("sub",             32'h402081b3, 16, 5,            7,      5'd2,  32'hfffffffe);
    testa("xor",             32'h0020c1b3, 16, 6,            3,      5'd3,  5);
    testa("or",              32'h0020e1b3, 16, 6,            3,      5'd4,  7);
    testa("and",             32'h0020f1b3, 16, 6,            3,      5'd5,  2);
    testa("sll",             32'h002091b3, 16, 1,            4,      5'd6,  16);
    testa("sll rs2=33",      32'h002091b3, 16, 1,            33,     5'd7,  2);
    testa("srl",             32'h0020d1b3, 16, 32'h80000000, 4,      5'd8,  32'h08000000);
    testa("sra",             32'h4020d1b3, 16, 32'h80000000, 4,      5'd9,  32'hf8000000);
    testa("slt -1 < 1",      32'h0020a1b3, 16, 32'hffffffff, 1,      5'd10, 1);
    testa("sltu -1 < 1",     32'h0020b1b3, 16, 32'hffffffff, 1,      5'd11, 0);

    // x3 = x1 op imm
    $display("--- Tipo I ---");
    testa("addi 4",          32'h00408193, 16, 10,           0,      5'd12, 14);
    testa("addi -4",         32'hffc08193, 16, 10,           0,      5'd13, 6);
    testa("addi 1030",       32'h40608193, 16, 10,           0,      5'd14, 1040);
    testa("slti 4",          32'h0040a193, 16, 3,            0,      5'd15, 1);
    testa("slti -1",         32'hfff0a193, 16, 0,            0,      5'd16, 0);
    testa("sltiu -1",        32'hfff0b193, 16, 5,            0,      5'd17, 1);
    testa("xori 4",          32'h0040c193, 16, 6,            0,      5'd18, 2);
    testa("ori 4",           32'h0040e193, 16, 3,            0,      5'd19, 7);
    testa("andi 4",          32'h0040f193, 16, 6,            0,      5'd20, 4);
    testa("slli 4",          32'h00409193, 16, 1,            0,      5'd21, 16);
    testa("srli 4",          32'h0040d193, 16, 32'h80000000, 0,      5'd22, 32'h08000000);
    testa("srai 4",          32'h4040d193, 16, 32'h80000000, 0,      5'd23, 32'hf8000000);

    $display("--- LUI / AUIPC ---");
    testa("lui 0x12345",     32'h123451b7, 16, 99,           99,     5'd24, 32'h12345000);
    testa("lui 0xfffff",     32'hfffff1b7, 16, 0,            0,      5'd25, 32'hfffff000);
    testa("auipc 1",         32'h00001197, 16, 0,            0,      5'd26, 32'h00001010);
    testa("auipc 0xfffff",   32'hfffff197, 16, 0,            0,      5'd27, 32'hfffff010);

    // r = endereco rs1 + imm
    $display("--- Load / Store ---");
    testa("lw 16(x1)",       32'h0100a183, 16, 100,          0,      5'd28, 116);
    testa("lw -4(x1)",       32'hffc0a183, 16, 100,          0,      5'd29, 96);
    testa("sw 8(x1)",        32'h0020a423, 16, 100,          55,     5'd30, 108);
    testa("sw -4(x1)",       32'hfe20ae23, 16, 100,          55,     5'd31, 96);

    $display("--- Sem envio ---");
    @(posedge clk); #1;
    testa_vazio("valido = 0");

    // Um envio por ciclo: cada resultado sai no ciclo seguinte
    $display("--- Envios seguidos ---");
    valido = 1'b1; instr = 32'h00408193; pc = 20; valor_rs1 = 1; rob_id = 5'd1;     // addi x3, x1, 4
    @(posedge clk); #1;
    if (wb !== 1'b1 || rid !== 5'd1 || r !== 32'd5) begin
        erros = erros + 1;
        $display("  [FALHA] envio 1 (addi): wb=%b rid=%0d r=%0d", wb, rid, r);
    end else
        $display("  [OK]    envio 1 (addi): rid=1 r=5");
    instr = 32'h002081b3; valor_rs1 = 5; valor_rs2 = 7; rob_id = 5'd2;              // add x3, x1, x2
    @(posedge clk); #1;
    if (wb !== 1'b1 || rid !== 5'd2 || r !== 32'd12) begin
        erros = erros + 1;
        $display("  [FALHA] envio 2 (add): wb=%b rid=%0d r=%0d", wb, rid, r);
    end else
        $display("  [OK]    envio 2 (add): rid=2 r=12");
    instr = 32'h0100a183; valor_rs1 = 100; rob_id = 5'd3;                           // lw x3, 16(x1)
    @(posedge clk); #1;
    valido = 1'b0;
    if (wb !== 1'b1 || rid !== 5'd3 || r !== 32'd116) begin
        erros = erros + 1;
        $display("  [FALHA] envio 3 (lw): wb=%b rid=%0d r=%0d", wb, rid, r);
    end else
        $display("  [OK]    envio 3 (lw): rid=3 r=116");
    @(posedge clk); #1;
    testa_vazio("ciclo seguinte");

    $display("--- Reset com envio ---");
    valido = 1'b1; rst = 1'b1; instr = 32'h00408193; valor_rs1 = 1; rob_id = 5'd4;  // addi
    @(posedge clk); #1;
    valido = 1'b0; rst = 1'b0;
    testa_vazio("reset");
    if (r !== 32'd0 || rid !== 5'd0) begin
        erros = erros + 1;
        $display("  [FALHA] reset: r=%h rid=%0d", r, rid);
    end else
        $display("  [OK]    reset: r=0 rid=0");

    $display("--- Erros: %0d ---", erros);
    $finish;
end

endmodule
