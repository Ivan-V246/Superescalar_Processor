module tb_caminho();

reg clk, rst;

reg        valido;
reg [31:0] instr;
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
    .rob_id(rob_id), .ready(ready),
    .wb(wb), .rid(rid), .r(r)
);

always #5 clk = ~clk;

// Envia uma instrucao, espera a resolucao e confere wb, rid e r
task testa;
    input [8*20-1:0] nome;
    input [31:0] _instr, _a, _b;
    input [4:0]  _id;
    input [31:0] r_esp;
    begin
        valido = 1'b1; instr = _instr;
        valor_rs1 = _a; valor_rs2 = _b; rob_id = _id;
        @(posedge clk); #1;
        valido = 1'b0;
        if (wb !== 1'b1 || rid !== _id || r !== r_esp) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b rid=%0d r=%h | esperado rid=%0d r=%h",
                     nome, wb, rid, r, _id, r_esp);
        end else
            $display("  [OK]    %0s: r=%h", nome, r);
    end
endtask

// Confere so wb e rid (resultado nao importa)
task testa_wb;
    input [8*20-1:0] nome;
    input [31:0] _instr;
    input [4:0]  _id;
    begin
        valido = 1'b1; instr = _instr;
        valor_rs1 = 32'd1; valor_rs2 = 32'd1; rob_id = _id;
        @(posedge clk); #1;
        valido = 1'b0;
        if (wb !== 1'b1 || rid !== _id) begin
            erros = erros + 1;
            $display("  [FALHA] %0s: wb=%b rid=%0d", nome, wb, rid);
        end else
            $display("  [OK]    %0s: wb=1 rid=%0d", nome, rid);
    end
endtask

initial begin
    clk = 0; rst = 1; erros = 0;
    valido = 0; instr = 0; valor_rs1 = 0; valor_rs2 = 0; rob_id = 0;

    @(posedge clk); #1;
    rst = 0;

    $display("--- Reset ---");
    if (wb !== 1'b0 || ready !== 1'b1) begin
        erros = erros + 1;
        $display("  [FALHA] wb=%b ready=%b", wb, ready);
    end else
        $display("  [OK]    wb=0 ready=1");

    // x3 = x1 op x2
    $display("--- Tipo R ---");
    testa("add",            32'h002081b3, 32'd5,        32'd7, 5'd1,  32'd12);
    testa("sub",            32'h402081b3, 32'd5,        32'd7, 5'd2,  32'hfffffffe);
    testa("xor",            32'h0020c1b3, 32'd6,        32'd3, 5'd3,  32'd5);
    testa("or",             32'h0020e1b3, 32'd6,        32'd3, 5'd4,  32'd7);
    testa("and",            32'h0020f1b3, 32'd6,        32'd3, 5'd5,  32'd2);
    testa("sll",            32'h002091b3, 32'd1,        32'd4, 5'd6,  32'd16);
    testa("sll rs2=33",     32'h002091b3, 32'd1,        32'd33, 5'd7, 32'd2);
    testa("srl",            32'h0020d1b3, 32'h80000000, 32'd4, 5'd8,  32'h08000000);
    testa("sra",            32'h4020d1b3, 32'h80000000, 32'd4, 5'd9,  32'hf8000000);
    testa("slt -1 < 1",     32'h0020a1b3, 32'hffffffff, 32'd1, 5'd10, 32'd1);
    testa("sltu -1 < 1",    32'h0020b1b3, 32'hffffffff, 32'd1, 5'd11, 32'd0);

    // x3 = x1 op imm
    $display("--- Tipo I ---");
    testa("addi 4",         32'h00408193, 32'd10,       32'd0, 5'd12, 32'd14);
    testa("addi -4",        32'hffc08193, 32'd10,       32'd0, 5'd13, 32'd6);
    testa("addi 1030",      32'h40608193, 32'd10,       32'd0, 5'd14, 32'd1040);  // AJUSTE 2
    testa("slti 4",         32'h0040a193, 32'd3,        32'd0, 5'd15, 32'd1);
    testa("slti -1",        32'hfff0a193, 32'd0,        32'd0, 5'd16, 32'd0);
    testa("sltiu -1",       32'hfff0b193, 32'd5,        32'd0, 5'd17, 32'd1);
    testa("xori 4",         32'h0040c193, 32'd6,        32'd0, 5'd18, 32'd2);
    testa("ori 4",          32'h0040e193, 32'd3,        32'd0, 5'd19, 32'd7);
    testa("andi 4",         32'h0040f193, 32'd6,        32'd0, 5'd20, 32'd4);
    testa("slli 4",         32'h00409193, 32'd1,        32'd0, 5'd21, 32'd16);
    testa("srli 4",         32'h0040d193, 32'h80000000, 32'd0, 5'd22, 32'h08000000);
    testa("srai 4",         32'h4040d193, 32'h80000000, 32'd0, 5'd23, 32'hf8000000); // AJUSTE 1

    $display("--- LUI ---");
    testa("lui 0x12345",    32'h123451b7, 32'd99,       32'd99, 5'd24, 32'h12345000);
    testa("lui 0xfffff",    32'hfffff1b7, 32'd0,        32'd0,  5'd25, 32'hfffff000);

    // r = endereco rs1 + imm
    $display("--- Load / Store ---");
    testa("lw 16(x1)",      32'h0100a183, 32'd100,      32'd0,  5'd26, 32'd116);
    testa("lw -4(x1)",      32'hffc0a183, 32'd100,      32'd0,  5'd27, 32'd96);
    testa("sw 8(x1)",       32'h0020a423, 32'd100,      32'd55, 5'd28, 32'd108);
    testa("sw -4(x1)",      32'hfe20ae23, 32'd100,      32'd55, 5'd29, 32'd96);

    // Fora do escopo: precisa responder para o ROB nao travar
    $display("--- Fora do escopo ---");
    testa_wb("beq",         32'h00208463, 5'd30);
    testa_wb("jal",         32'h0000006f, 5'd31);

    $display("--- Sem envio ---");
    @(posedge clk); #1;
    if (wb !== 1'b0) begin
        erros = erros + 1;
        $display("  [FALHA] wb=%b esperado 0", wb);
    end else
        $display("  [OK]    wb=0");

    $display("--- Envios seguidos ---");
    valido = 1'b1; instr = 32'h00408193; valor_rs1 = 32'd1; rob_id = 5'd1;
    @(posedge clk); #1;
    if (wb !== 1'b1 || rid !== 5'd1 || r !== 32'd5) begin
        erros = erros + 1;
        $display("  [FALHA] envio 1: wb=%b rid=%0d r=%h", wb, rid, r);
    end else
        $display("  [OK]    envio 1: rid=1 r=%h", r);
    instr = 32'h00808193; valor_rs1 = 32'd1; rob_id = 5'd2;
    @(posedge clk); #1;
    valido = 1'b0;
    if (wb !== 1'b1 || rid !== 5'd2 || r !== 32'd9) begin
        erros = erros + 1;
        $display("  [FALHA] envio 2: wb=%b rid=%0d r=%h", wb, rid, r);
    end else
        $display("  [OK]    envio 2: rid=2 r=%h", r);

    $display("--- Reset com envio ---");
    valido = 1'b1; rst = 1'b1; instr = 32'h00408193; rob_id = 5'd3;
    @(posedge clk); #1;
    valido = 1'b0; rst = 1'b0;
    if (wb !== 1'b0) begin
        erros = erros + 1;
        $display("  [FALHA] wb=%b esperado 0", wb);
    end else
        $display("  [OK]    wb=0");

    $display("--- Erros: %0d ---", erros);
    $finish;
end

endmodule
