module rob_tb();

reg clk, rst;

reg [2:0]  v;
reg [2:0]  dst1, dst2, dst3;
reg [4:0]  rd1, rd2, rd3;

reg [2:0]  wb;
reg [4:0]  rid1, rid2, rid3;
reg [31:0] r1, r2, r3;

// Dummy — Load Buffer
reg  [4:0]  lrid_dummy;
wire        lready;
wire [31:0] laddr;
reg         lb_done;
reg  [4:0]  lb_rid;

// Dummy — Store Buffer
reg  [4:0]  srid_dummy;
wire [31:0] saddr;

// Saídas do ROB
wire [2:0]  cdst1, cdst2, cdst3;
wire [4:0]  crid1, crid2, crid3;
wire [4:0]  crob_id1, crob_id2, crob_id3;
wire [31:0] cr1, cr2, cr3;
wire        stop;
wire [4:0]  rob_tail;

rob U_rob (
    .clk(clk), .rst(rst),
    .v(v),
    .dst1(dst1), .dst2(dst2), .dst3(dst3),
    .rd1(rd1), .rd2(rd2), .rd3(rd3),
    .wb(wb),
    .rid1(rid1), .rid2(rid2), .rid3(rid3),
    .r1(r1), .r2(r2), .r3(r3),
    .cdst1(cdst1), .cdst2(cdst2), .cdst3(cdst3),
    .crid1(crid1), .crid2(crid2), .crid3(crid3),
    .crob_id1(crob_id1), .crob_id2(crob_id2), .crob_id3(crob_id3),
    .cr1(cr1), .cr2(cr2), .cr3(cr3),
    .lrid(lrid_dummy), .lready(lready), .laddr(laddr),
    .lb_done(lb_done), .lb_rid(lb_rid),
    .srid(srid_dummy), .saddr(saddr),
    .stop(stop),
    .rob_tail(rob_tail)
);

always #5 clk = ~clk;

// ─── Tasks ───────────────────────────────────────────────

task despacha;
    input [2:0]  _v;
    input [2:0]  _dst1, _dst2, _dst3;
    input [4:0]  _rd1, _rd2, _rd3;
    begin
        v = _v;
        dst1 = _dst1; dst2 = _dst2; dst3 = _dst3;
        rd1 = _rd1; rd2 = _rd2; rd3 = _rd3;
        @(posedge clk); #1;
        v = 3'b0;
    end
endtask

task despacha_safe;
    input [2:0]  _v;
    input [2:0]  _dst1, _dst2, _dst3;
    input [4:0]  _rd1, _rd2, _rd3;
    begin
        if(stop) begin
            $display("  [BLOQUEADO] stop=1, mandando validos=0");
            v = 3'b0;
            @(posedge clk); #1;
        end else begin
            v = _v;
            dst1 = _dst1; dst2 = _dst2; dst3 = _dst3;
            rd1 = _rd1; rd2 = _rd2; rd3 = _rd3;
            @(posedge clk); #1;
            v = 3'b0;
        end
    end
endtask

task writeback;
    input [2:0]  _wb;
    input [4:0]  _rid1, _rid2, _rid3;
    input [31:0] _r1, _r2, _r3;
    begin
        wb = _wb;
        rid1 = _rid1; rid2 = _rid2; rid3 = _rid3;
        r1 = _r1; r2 = _r2; r3 = _r3;
        @(posedge clk); #1;
        wb = 3'b0;
    end
endtask

task mostra_estado;
    begin
        $display("  tail=%0d head=%0d ocupacao=%0d stop=%b rob_tail=%0d",
            U_rob.tail, U_rob.head,
            U_rob.tail - U_rob.head, stop, rob_tail);
        $display("  cdst1=%03b cdst2=%03b cdst3=%03b",
            cdst1, cdst2, cdst3);
        $display("  crob_id1=%0d crob_id2=%0d crob_id3=%0d",
            crob_id1, crob_id2, crob_id3);
        $display("  cr1=%0d cr2=%0d cr3=%0d", cr1, cr2, cr3);
    end
endtask

// ─── Testes ──────────────────────────────────────────────

initial begin
    $dumpfile("rob.vcd");
    $dumpvars(0, rob_tb);

    clk = 0; rst = 1;
    v = 3'b0;
    {dst1,dst2,dst3} = 9'b0;
    {rd1,rd2,rd3}    = 15'b0;
    wb = 3'b0;
    {rid1,rid2,rid3} = 15'b0;
    {r1,r2,r3}       = 96'b0;
    lb_done = 0; lb_rid = 5'b0;
    lrid_dummy = 5'b0;
    srid_dummy = 5'b0;
    @(posedge clk); #1;
    rst = 0;

    // dst: 001=banco, 010=load, 011=banco+pc, 100=store, 000=nada

    $display("\n=== TESTE 1: Despacha 3 instrucoes ===");
    despacha(3'b111, 3'b001,3'b001,3'b000, 5'd1,5'd2,5'd3);
    mostra_estado;

    $display("\n=== TESTE 2: Despacha 2 instrucoes ===");
    despacha(3'b011, 3'b001,3'b000,3'b000, 5'd4,5'd5,5'd0);
    mostra_estado;

    $display("\n=== TESTE 3: Despacha 1 instrucao (Load) ===");
    despacha(3'b001, 3'b010,3'b000,3'b000, 5'd0,5'd0,5'd0);
    mostra_estado;

    $display("\n=== TESTE 4: Writeback em ordem (rob 0,1,2) ===");
    writeback(3'b111, 5'd0,5'd1,5'd2, 32'd100,32'd200,32'd300);
    #2; mostra_estado;

    $display("\n=== TESTE 5: Writeback fora de ordem ===");
    $display("  Escreve rob 4 antes do rob 3 — head nao deve avancar");
    writeback(3'b001, 5'd4,5'd0,5'd0, 32'd400,32'd0,32'd0);
    #2; mostra_estado;

    $display("\n  Agora escreve rob 3 — head deve avancar 2");
    writeback(3'b001, 5'd3,5'd0,5'd0, 32'd300,32'd0,32'd0);
    #2; mostra_estado;

    $display("\n=== TESTE 6: Writeback Load — seta addr_ready, nao ready ===");
    writeback(3'b001, 5'd5,5'd0,5'd0, 32'd999,32'd0,32'd0);
    #2; mostra_estado;
    $display("  Load Buffer sinaliza lb_done...");
    lb_done = 1; lb_rid = 5'd5;
    @(posedge clk); #1;
    lb_done = 0;
    #2; mostra_estado;

    $display("\n=== TESTE 7: Reset ===");
    rst = 1;
    @(posedge clk); #1;
    rst = 0;
    mostra_estado;

    $display("\n=== TESTE 8: Enchendo buffer ate stop ===");
    repeat(10) begin
        despacha_safe(3'b111, 3'b001,3'b001,3'b001, 5'd0,5'd0,5'd0);
        $display("  tail=%0d head=%0d ocupacao=%0d stop=%b",
            U_rob.tail, U_rob.head,
            U_rob.tail - U_rob.head, stop);
    end

    $display("\n=== TESTE 9: Tenta despachar com buffer cheio ===");
    repeat(3) begin
        despacha_safe(3'b111, 3'b001,3'b010,3'b100, 5'd10,5'd11,5'd12);
        $display("  tail=%0d head=%0d ocupacao=%0d stop=%b",
            U_rob.tail, U_rob.head,
            U_rob.tail - U_rob.head, stop);
    end

    $display("\n=== TESTE 10: Commit de 6, depois despacha 6 ===");
    writeback(3'b111, 5'd0,5'd1,5'd2, 32'd1,32'd2,32'd3);
    #2; mostra_estado;
    writeback(3'b111, 5'd3,5'd4,5'd5, 32'd4,32'd5,32'd6);
    #2; mostra_estado;

    $display("\n  Stop sumiu, despachando 6 novas com ponteiros diferentes...");
    repeat(2) begin
        despacha_safe(3'b111, 3'b001,3'b010,3'b100, 5'd10,5'd11,5'd12);
        $display("  tail=%0d head=%0d ocupacao=%0d stop=%b",
            U_rob.tail, U_rob.head,
            U_rob.tail - U_rob.head, stop);
    end

    $display("\nFim dos testes.");
    #20;
    $finish;
end

endmodule
