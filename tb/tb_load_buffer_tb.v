module load_buffer_tb();

reg clk, rst;

reg [2:0] v;
reg [2:0] dst1, dst2, dst3;
reg [4:0] rob_id1, rob_id2, rob_id3;

reg        lready;
reg [31:0] mem_data;
reg        mem_done;

reg [2:0]  cv;
reg [4:0]  crob_id1, crob_id2, crob_id3;

wire [4:0]  lrid;
wire        mem_req;
wire        lb_done;
wire [4:0]  lb_rid;
wire [31:0] lb_dado1, lb_dado2, lb_dado3;
wire        stop;

load_buffer U_lb (
    .clk(clk), .rst(rst),
    .v(v),
    .dst1(dst1), .dst2(dst2), .dst3(dst3),
    .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
    .lrid(lrid), .lready(lready),
    .mem_req(mem_req), .mem_data(mem_data), .mem_done(mem_done),
    .lb_done(lb_done), .lb_rid(lb_rid),
    .cv(cv), .crob_id1(crob_id1), .crob_id2(crob_id2), .crob_id3(crob_id3),
    .lb_dado1(lb_dado1), .lb_dado2(lb_dado2), .lb_dado3(lb_dado3),
    .stop(stop)
);

always #5 clk = ~clk;

always @(posedge mem_done) begin
    $display("  [MEM_DONE] lb_rid=%0d", lb_rid);
end

always @(posedge lb_done) begin
    $display("  [LB_DONE] rob_id=%0d", lb_rid);
end

always @(posedge clk) begin
    #1;
    if(|U_lb.commit1)
        $display("  [COMMIT] crob=%0d/%0d/%0d head_rob_id=%0d commit1=%b commit2=%b commit3=%b",
            crob_id1, crob_id2, crob_id3,
            U_lb.buffer[U_lb.head[3:0]][36:32],
            U_lb.commit1, U_lb.commit2, U_lb.commit3);
end

// ─── Tasks ───────────────────────────────────────────────

task despacha;
    input [2:0]  _v;
    input [2:0]  _dst1, _dst2, _dst3;
    input [4:0]  _rob_id1, _rob_id2, _rob_id3;
    begin
        $display("  [DESPACHO] v=%03b dst=%03b/%03b/%03b rob_ids=%0d/%0d/%0d is_load=%b%b%b",
            _v, _dst1, _dst2, _dst3, _rob_id1, _rob_id2, _rob_id3,
            _v[0]&(_dst1==3'b010), _v[1]&(_dst2==3'b010), _v[2]&(_dst3==3'b010));
        v = _v; dst1 = _dst1; dst2 = _dst2; dst3 = _dst3;
        rob_id1 = _rob_id1; rob_id2 = _rob_id2; rob_id3 = _rob_id3;
        @(posedge clk); #1;
        v = 3'b0;
    end
endtask

task executa_load;
    input [31:0] _addr;
    input [31:0] _data;
    input integer addr_ciclos;
    input integer mem_ciclos;
    begin
        repeat(addr_ciclos) @(posedge clk);
        #1;
        lready = 1;
        $display("  [ROB] lrid=%0d endereço pronto: 0x%08h", lrid, _addr);
        repeat(mem_ciclos) @(posedge clk);
        #1;
        mem_data = _data;
        mem_done = 1;
        $display("  [MEM] dado=%0d", _data);
        @(posedge clk); #1;
        mem_done = 0;
        lready   = 0;
    end
endtask

task commita;
    input [2:0]  _cv;
    input [4:0]  _crob_id1, _crob_id2, _crob_id3;
    begin
        cv = _cv;
        crob_id1 = _crob_id1; crob_id2 = _crob_id2; crob_id3 = _crob_id3;
        @(posedge clk); #1;
        cv = 3'b0;
    end
endtask

task mostra_estado;
    begin
        $display("  LB: head=%0d mem_ptr=%0d tail=%0d stop=%b",
            U_lb.head, U_lb.mem_ptr, U_lb.tail, stop);
        $display("  lrid=%0d lready=%b mem_req=%b lb_done=%b lb_rid=%0d",
            lrid, lready, mem_req, lb_done, lb_rid);
        $display("  dado1=%0d dado2=%0d dado3=%0d",
            lb_dado1, lb_dado2, lb_dado3);
        $display("  is_load=%b%b%b dispatched=%0d",
            U_lb.is_load1, U_lb.is_load2, U_lb.is_load3, U_lb.dispatched);
    end
endtask

// ─── Testes ──────────────────────────────────────────────
// Mapa de rob_ids:
// Teste 1: rob_id=0 (Load)
// Teste 2: rob_id=1 (ADD), rob_id=2 (Load) — Load no slot 2
// Teste 3: rob_id=3 (Load), rob_id=4 (ADD), rob_id=5 (Load) — Loads nos slots 1 e 3
// Teste 4: rob_id=6,7,8 (3 Loads)
// Teste 5: enche até stop
// Teste 6: reset

initial begin
    $dumpfile("load_buffer.vcd");
    $dumpvars(0, load_buffer_tb);

    clk = 0; rst = 1;
    v = 3'b0; {dst1,dst2,dst3} = 9'b0;
    {rob_id1,rob_id2,rob_id3} = 15'b0;
    lready = 0; mem_data = 32'b0; mem_done = 0;
    cv = 3'b0; {crob_id1,crob_id2,crob_id3} = 15'b0;
    @(posedge clk); #1;
    rst = 0;

    // ── Teste 1: 1 Load no slot 1 ──
    // rob_id=0: Load
    $display("\n=== TESTE 1: 1 Load no slot 1 (rob_id=0) ===");
    despacha(3'b001, 3'b010, 3'b000, 3'b000, 5'd0, 5'd0, 5'd0);
    mostra_estado;
    executa_load(32'hAAAA0000, 32'd100, 1, 2);
    mostra_estado;
    commita(3'b001, 5'd0, 5'd0, 5'd0);
    mostra_estado;

    // ── Teste 2: ADD no slot 1, Load no slot 2 ──
    // rob_id=1: ADD
    // rob_id=2: Load
    $display("\n=== TESTE 2: ADD slot1 + Load slot2 (rob_ids 1,2) ===");
    despacha(3'b011, 3'b001, 3'b010, 3'b000, 5'd1, 5'd2, 5'd0);
    mostra_estado;
    executa_load(32'hBBBB0002, 32'd200, 1, 3);
    mostra_estado;
    commita(3'b011, 5'd1, 5'd2, 5'd0);
    mostra_estado;

    // ── Teste 3: Load slot1 + ADD slot2 + Load slot3 ──
    // rob_id=3: Load
    // rob_id=4: ADD
    // rob_id=5: Load
    $display("\n=== TESTE 3: Load+ADD+Load (rob_ids 3,4,5) ===");
    despacha(3'b111, 3'b010, 3'b001, 3'b010, 5'd3, 5'd4, 5'd5);
    mostra_estado;

    // Load rob_id=3
    executa_load(32'hCCCC0003, 32'd300, 1, 2);
    mostra_estado;
    // Load rob_id=5
    executa_load(32'hCCCC0005, 32'd500, 1, 2);
    mostra_estado;
    commita(3'b111, 5'd3, 5'd4, 5'd5);
    mostra_estado;

    // ── Teste 4: 3 Loads simultaneos ──
    // rob_id=6,7,8: Loads
    $display("\n=== TESTE 4: 3 Loads simultaneos (rob_ids 6,7,8) ===");
    despacha(3'b111, 3'b010, 3'b010, 3'b010, 5'd6, 5'd7, 5'd8);
    mostra_estado;
    executa_load(32'hDDDD0006, 32'd400, 1, 3);
    mostra_estado;
    executa_load(32'hDDDD0007, 32'd500, 1, 3);
    mostra_estado;
    executa_load(32'hDDDD0008, 32'd600, 1, 3);
    mostra_estado;
    commita(3'b111, 5'd6, 5'd7, 5'd8);
    mostra_estado;

    // ── Teste 5: Enche até stop ──
    $display("\n=== TESTE 5: Enchendo LB ate stop ===");
    begin : enche
        integer j;
        for(j = 0; j < 6; j = j + 1) begin
            despacha(3'b011, 3'b010, 3'b010, 3'b000,
                     5'd9+j*2, 5'd10+j*2, 5'd0);
            $display("  head=%0d tail=%0d stop=%b",
                U_lb.head, U_lb.tail, stop);
        end
    end

    // ── Teste 6: Reset ──
    $display("\n=== TESTE 6: Reset ===");
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
