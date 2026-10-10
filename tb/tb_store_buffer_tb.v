module store_buffer_tb();

reg clk, rst;

reg [2:0]  v;
reg [2:0]  dst1, dst2, dst3;
reg [4:0]  rob_id1, rob_id2, rob_id3;
reg [31:0] dado1, dado2, dado3;

reg [2:0]  cv;
reg [4:0]  crob_id1, crob_id2, crob_id3;
reg [31:0] saddr_sim;

wire [4:0]  srid;
wire        mem_req;
wire [31:0] mem_addr;
wire [31:0] mem_dado;
wire        stop;

store_buffer U_sb (
    .clk(clk), .rst(rst),
    .v(v),
    .dst1(dst1), .dst2(dst2), .dst3(dst3),
    .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
    .dado1(dado1), .dado2(dado2), .dado3(dado3),
    .srid(srid),
    .saddr(saddr_sim),
    .cv(cv),
    .crob_id1(crob_id1), .crob_id2(crob_id2), .crob_id3(crob_id3),
    .mem_req(mem_req),
    .mem_addr(mem_addr),
    .mem_dado(mem_dado),
    .stop(stop)
);

always #5 clk = ~clk;

// Monitor — captura na borda de subida do mem_req
always @(posedge mem_req) begin
    $display("  [MEM_WR] addr=0x%08h dado=%0d", mem_addr, mem_dado);
end

// ─── Tasks ───────────────────────────────────────────────

task despacha;
    input [2:0]  _v;
    input [2:0]  _dst1, _dst2, _dst3;
    input [4:0]  _rob_id1, _rob_id2, _rob_id3;
    input [31:0] _dado1, _dado2, _dado3;
    begin
        $display("  [DESPACHO] v=%03b dst=%03b/%03b/%03b rob_ids=%0d/%0d/%0d is_store=%b%b%b",
            _v, _dst1, _dst2, _dst3, _rob_id1, _rob_id2, _rob_id3,
            _v[0]&(_dst1==3'b100), _v[1]&(_dst2==3'b100), _v[2]&(_dst3==3'b100));
        v = _v; dst1 = _dst1; dst2 = _dst2; dst3 = _dst3;
        rob_id1 = _rob_id1; rob_id2 = _rob_id2; rob_id3 = _rob_id3;
        dado1 = _dado1; dado2 = _dado2; dado3 = _dado3;
        @(posedge clk); #1;
        v = 3'b0;
    end
endtask

task commita;
    input [2:0]  _cv;
    input [4:0]  _crob_id1, _crob_id2, _crob_id3;
    input [31:0] _saddr;
    begin
        // Seta saddr ANTES do clock — captura no momento certo
        saddr_sim = _saddr;
        cv = _cv;
        crob_id1 = _crob_id1; crob_id2 = _crob_id2; crob_id3 = _crob_id3;
        // Mostra antes do clock
        if(U_sb.commit)
            $display("  [COMMIT] srid=%0d saddr=0x%08h dado=%0d",
                srid, saddr_sim, mem_dado);
        @(posedge clk); #1;
        cv = 3'b0;
    end
endtask

task mostra_estado;
    begin
        $display("  SB: head=%0d tail=%0d stop=%b",
            U_sb.head, U_sb.tail, stop);
        $display("  srid=%0d saddr=0x%08h mem_req=%b mem_dado=%0d",
            srid, saddr_sim, mem_req, mem_dado);
        $display("  is_store=%b%b%b dispatched=%0d",
            U_sb.is_store1, U_sb.is_store2, U_sb.is_store3, U_sb.dispatched);
    end
endtask

// ─── Testes ──────────────────────────────────────────────

initial begin
    $dumpfile("store_buffer.vcd");
    $dumpvars(0, store_buffer_tb);

    clk = 0; rst = 1;
    v = 3'b0; {dst1,dst2,dst3} = 9'b0;
    {rob_id1,rob_id2,rob_id3} = 15'b0;
    {dado1,dado2,dado3} = 96'b0;
    cv = 3'b0; {crob_id1,crob_id2,crob_id3} = 15'b0;
    saddr_sim = 32'b0;

    @(posedge clk); #1;
    rst = 0;

    // ── Teste 1: 1 Store slot1 ──
    $display("\n=== TESTE 1: 1 Store slot1 (rob_id=0, dado=100) ===");
    despacha(3'b001, 3'b100, 3'b000, 3'b000,
             5'd0, 5'd0, 5'd0,
             32'd100, 32'd0, 32'd0);
    mostra_estado;
    commita(3'b001, 5'd0, 5'd0, 5'd0, 32'hAAAA0000);
    mostra_estado;

    // ── Teste 2: ADD slot1 + Store slot2 ──
    $display("\n=== TESTE 2: ADD slot1 + Store slot2 (rob_ids 1,2) ===");
    despacha(3'b011, 3'b001, 3'b100, 3'b000,
             5'd1, 5'd2, 5'd0,
             32'd0, 32'd200, 32'd0);
    mostra_estado;
    commita(3'b011, 5'd1, 5'd2, 5'd0, 32'hBBBB0002);
    mostra_estado;

    // ── Teste 3: Store slot1 + ADD slot2 + Store slot3 ──
    $display("\n=== TESTE 3: Store+ADD+Store (rob_ids 3,4,5) ===");
    despacha(3'b111, 3'b100, 3'b001, 3'b100,
             5'd3, 5'd4, 5'd5,
             32'd300, 32'd0, 32'd400);
    mostra_estado;
    commita(3'b111, 5'd3, 5'd4, 5'd5, 32'hCCCC0003);
    mostra_estado;
    commita(3'b001, 5'd5, 5'd0, 5'd0, 32'hCCCC0005);
    mostra_estado;

    // ── Teste 4: 3 Stores simultâneos ──
    $display("\n=== TESTE 4: 3 Stores simultaneos (rob_ids 6,7,8) ===");
    despacha(3'b111, 3'b100, 3'b100, 3'b100,
             5'd6, 5'd7, 5'd8,
             32'd500, 32'd600, 32'd700);
    mostra_estado;
    commita(3'b111, 5'd6, 5'd7, 5'd8, 32'hDDDD0006);
    mostra_estado;
    commita(3'b001, 5'd7, 5'd0, 5'd0, 32'hDDDD0007);
    mostra_estado;
    commita(3'b001, 5'd8, 5'd0, 5'd0, 32'hDDDD0008);
    mostra_estado;

    // ── Teste 5: Commit fora de ordem ──
    $display("\n=== TESTE 5: Commit fora de ordem (rob_ids 9,10) ===");
    despacha(3'b011, 3'b100, 3'b100, 3'b000,
             5'd9, 5'd10, 5'd0,
             32'd800, 32'd900, 32'd0);
    mostra_estado;
    $display("  Commita rob_id=10 antes do 9 — head nao deve avancar");
    commita(3'b001, 5'd10, 5'd0, 5'd0, 32'hEEEE0010);
    mostra_estado;
    $display("  Agora commita rob_id=9 — head avanca");
    commita(3'b001, 5'd9, 5'd0, 5'd0, 32'hEEEE0009);
    mostra_estado;
    commita(3'b001, 5'd10, 5'd0, 5'd0, 32'hEEEE0010);
    mostra_estado;

    // ── Teste 6: Enche até stop ──
    $display("\n=== TESTE 6: Enchendo SB ate stop ===");
    begin : enche
        integer j;
        for(j = 0; j < 6; j = j + 1) begin
            despacha(3'b011, 3'b100, 3'b100, 3'b000,
                     5'd11+j*2, 5'd12+j*2, 5'd0,
                     32'd1000+j, 32'd2000+j, 32'd0);
            $display("  head=%0d tail=%0d stop=%b",
                U_sb.head, U_sb.tail, stop);
        end
    end

    // ── Teste 7: Reset ──
    $display("\n=== TESTE 7: Reset ===");
    mostra_estado;
    rst = 1;
    @(posedge clk); #1;
    rst = 0;
    mostra_estado;

    $display("\nFim dos testes.");
    #20;
    $finish;
end

endmodule
