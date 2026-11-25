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

// Saídas do ROB
wire [2:0]  cdst1, cdst2, cdst3;
wire [4:0]  crid1, crid2, crid3;
wire [4:0]  crob_id1, crob_id2, crob_id3;
wire [31:0] cr1, cr2, cr3;
wire        stop;
wire [4:0]  rob_tail;

//IVAN FEATURE: recuperação
reg         flush;
reg  [4:0]  flush_rob_id;
wire        flush_ok;
integer     erros = 0;
integer     k;

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
    .stop(stop),
    .rob_tail(rob_tail),
    //IVAN FEATURE
    .flush(flush), .flush_rob_id(flush_rob_id), .flush_ok(flush_ok)
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

//IVAN FEATURE
task checa;
    input cond;
    input [8*48-1:0] nome;
    begin
        if (cond !== 1'b1) begin
            $display("FALHOU: %0s", nome);
            erros = erros + 1;
        end else begin
            $display("PASSOU: %0s", nome);
        end
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
    flush = 0; flush_rob_id = 5'd0;  //IVAN FEATURE
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

    //IVAN FEATURE: testes verificados da recuperação
    $display("\n=== TESTE 11: Recuperacao (flush) ===");
    rst = 1; @(posedge clk); #1; rst = 0;
    despacha(3'b111, 3'b000,3'b000,3'b000, 5'd1,5'd2,5'd3);   // rob 0,1,2 (2 = desvio B)
    despacha(3'b111, 3'b000,3'b000,3'b000, 5'd4,5'd5,5'd6);   // rob 3,4,5 (mais novas)
    writeback(3'b011, 5'd3,5'd4,5'd0, 32'd33,32'd44,32'd0);   // 3 e 4 terminam antes do flush

    // Ciclo do flush: B termina, erra, e o despacho tenta alocar (caminho errado)
    wb = 3'b001; rid1 = 5'd2; r1 = 32'd22;
    flush = 1; flush_rob_id = 5'd2;
    v = 3'b111; {dst1,dst2,dst3} = 9'b0; {rd1,rd2,rd3} = {5'd20,5'd21,5'd22};
    #1;
    checa(flush_ok === 1'b1, "flush de B valido");
    @(posedge clk); #1;
    wb = 0; flush = 0; v = 0;
    checa(U_rob.tail === 6'd3, "tail volta para B+1");
    checa(U_rob.ready[2] === 1'b1, "B recebe o proprio resultado");
    checa(U_rob.ready[3] === 1'b0 && U_rob.ready[4] === 1'b0,
          "entradas mais novas que B limpas");
    checa(U_rob.rd[6] !== 5'd20, "alocacao do ciclo do flush ignorada");

    // Resultados atrasados de instruções descartadas
    writeback(3'b001, 5'd5,5'd0,5'd0, 32'd55,32'd0,32'd0);
    checa(U_rob.ready[5] === 1'b0, "wb atrasado ignorado");
    lb_done = 1; lb_rid = 5'd4; @(posedge clk); #1; lb_done = 0;
    checa(U_rob.ready[4] === 1'b0, "lb_done atrasado ignorado");

    // Flush de um desvio já descartado
    flush = 1; flush_rob_id = 5'd4; #1;
    checa(flush_ok === 1'b0, "flush de desvio descartado ignorado");
    @(posedge clk); #1; flush = 0;
    checa(U_rob.tail === 6'd3, "tail inalterado");

    // O commit não passa do tail
    writeback(3'b011, 5'd0,5'd1,5'd0, 32'd10,32'd11,32'd0);
    @(posedge clk); #1;
    @(posedge clk); #1;
    checa(U_rob.head === 6'd3, "commit para no tail (head = 3)");

    $display("\n=== TESTE 12: wb no mesmo ciclo do flush ===");
    despacha(3'b111, 3'b000,3'b000,3'b000, 5'd7,5'd8,5'd9);   // rob 3,4,5
    wb = 3'b011; rid1 = 5'd3; r1 = 32'd1; rid2 = 5'd4; r2 = 32'd2;  // B=3 e a mais nova 4
    flush = 1; flush_rob_id = 5'd3;
    @(posedge clk); #1;
    wb = 0; flush = 0;
    checa(U_rob.ready[3] === 1'b1, "B pronto");
    checa(U_rob.ready[4] === 1'b0, "wb da mais nova perde para a limpeza");
    checa(U_rob.tail === 6'd4, "tail = B+1");

    // O head precisa já ter dado uma volta (bit de volta = 1) para testar a conta do tail
    $display("\n=== TESTE 13: flush com volta do head (31 -> 0) ===");
    rst = 1; @(posedge clk); #1; rst = 0;
    for (k = 0; k < 20; k = k + 1) begin
        despacha(3'b111, 3'b000,3'b000,3'b000, 5'd1,5'd1,5'd1);
        writeback(3'b111, (k*3) % 32, (k*3+1) % 32, (k*3+2) % 32, 32'd0,32'd0,32'd0);
    end
    @(posedge clk); #1;
    checa(U_rob.head === 6'd60 && U_rob.tail === 6'd60, "head e tail em 60 (posicao 28, segunda volta)");
    despacha(3'b111, 3'b000,3'b000,3'b000, 5'd1,5'd1,5'd1);   // rob 28,29,30
    despacha(3'b111, 3'b000,3'b000,3'b000, 5'd1,5'd1,5'd1);   // rob 31,0,1
    writeback(3'b011, 5'd0,5'd1,5'd0, 32'd0,32'd0,32'd0);     // 0 e 1 (mais novas que B) terminam
    flush = 1; flush_rob_id = 5'd31;
    @(posedge clk); #1; flush = 0;
    checa(U_rob.tail === 6'd0, "tail = 64 -> 0 (posicao 0, bit de volta certo)");
    checa(U_rob.ready[0] === 1'b0 && U_rob.ready[1] === 1'b0,
          "entradas depois da volta limpas");
    checa((U_rob.tail - U_rob.head) === 6'd4,
          "entradas antes de B e B mantidas (28..31)");

    //IVAN FEATURE: Commit e flush no mesmo ciclo
    // rob 0..5; 0, 1 e 2 prontos fazem commit no ciclo em que B = 3 erra
    $display("\n=== TESTE 14: commit e flush no mesmo ciclo ===");
    rst = 1; @(posedge clk); #1; rst = 0;
    despacha(3'b111, 3'b000,3'b000,3'b000, 5'd1,5'd2,5'd3);   // rob 0,1,2
    despacha(3'b111, 3'b000,3'b000,3'b000, 5'd4,5'd5,5'd6);   // rob 3 (B),4,5
    writeback(3'b111, 5'd0,5'd1,5'd2, 32'd10,32'd11,32'd12);  // 0, 1 e 2 prontos
    wb = 3'b011; rid1 = 5'd3; r1 = 32'd33; rid2 = 5'd4; r2 = 32'd44;  // B e a mais nova 4
    flush = 1; flush_rob_id = 5'd3;
    #1;
    checa(flush_ok === 1'b1, "flush valido com commit no mesmo ciclo");
    checa(crob_id1 === 5'd0 && crob_id2 === 5'd1 && crob_id3 === 5'd2, "0, 1 e 2 commitando");
    @(posedge clk); #1;
    wb = 0; flush = 0;
    checa(U_rob.head === 6'd3, "head avanca pelo commit (3)");
    checa(U_rob.tail === 6'd4, "tail = B+1 (4)");
    checa(U_rob.ready[3] === 1'b1, "B pronto");
    checa(U_rob.ready[4] === 1'b0 && U_rob.ready[5] === 1'b0,
          "entradas mais novas que B limpas");
    checa(U_rob.ready[0] === 1'b0 && U_rob.ready[2] === 1'b0,
          "commitadas liberadas");
    @(posedge clk); #1;
    checa(U_rob.head === 6'd4 && U_rob.tail === 6'd4, "B commita e o ROB esvazia");

    if (erros == 0)
        $display("\nTESTES VERIFICADOS PASSARAM");
    else
        $display("\n%0d ERRO(S)", erros);
    $display("\nFim dos testes.");
    #20;
    $finish;
end

endmodule
