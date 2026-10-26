module store_buffer_tb();

reg clk, rst;

reg [2:0]  v;
reg [2:0]  dst1, dst2, dst3;
reg [31:0] dado1, dado2, dado3;

reg [2:0]  cv;
reg [31:0] cr1, cr2, cr3;

wire        mem_req;
wire [31:0] mem_addr;
wire [31:0] mem_dado;
wire        stop;

integer erros = 0;

store_buffer U_sb (
    .clk(clk), .rst(rst),
    .v(v),
    .dst1(dst1), .dst2(dst2), .dst3(dst3),
    .dado1(dado1), .dado2(dado2), .dado3(dado3),
    .cv(cv),
    .cr1(cr1), .cr2(cr2), .cr3(cr3),
    .mem_req(mem_req),
    .mem_addr(mem_addr),
    .mem_dado(mem_dado),
    .stop(stop)
);

always #5 clk = ~clk;

// ─── Escritas esperadas na memória, em ordem ─────────────
reg [31:0] esp_addr [0:31];
reg [31:0] esp_dado [0:31];
integer n_esp = 0;  // quantas escritas são esperadas
integer n_wr  = 0;  // quantas escritas aconteceram

task espera_escrita;
    input [31:0] _addr, _dado;
    begin
        esp_addr[n_esp] = _addr;
        esp_dado[n_esp] = _dado;
        n_esp = n_esp + 1;
    end
endtask

// Monitor — cada ciclo com mem_req é uma escrita na memória
always @(posedge clk) begin
    if (!rst && mem_req) begin
        if (n_wr >= n_esp) begin
            $display("  FALHOU: escrita inesperada addr=0x%08h dado=%0d", mem_addr, mem_dado);
            erros = erros + 1;
        end else if (mem_addr !== esp_addr[n_wr] || mem_dado !== esp_dado[n_wr]) begin
            $display("  FALHOU: escrita %0d addr=0x%08h dado=%0d, esperado addr=0x%08h dado=%0d",
                n_wr, mem_addr, mem_dado, esp_addr[n_wr], esp_dado[n_wr]);
            erros = erros + 1;
        end else begin
            $display("  [MEM_WR] addr=0x%08h dado=%0d", mem_addr, mem_dado);
        end
        n_wr = n_wr + 1;
    end
end

// ─── Tasks ───────────────────────────────────────────────

task despacha;
    input [2:0]  _v;
    input [2:0]  _dst1, _dst2, _dst3;
    input [31:0] _dado1, _dado2, _dado3;
    begin
        v = _v; dst1 = _dst1; dst2 = _dst2; dst3 = _dst3;
        dado1 = _dado1; dado2 = _dado2; dado3 = _dado3;
        @(posedge clk); #1;
        v = 3'b0;
    end
endtask

task commita;
    input [2:0]  _cv;
    input [31:0] _cr1, _cr2, _cr3;
    begin
        cv = _cv; cr1 = _cr1; cr2 = _cr2; cr3 = _cr3;
        @(posedge clk); #1;
        cv = 3'b0;
    end
endtask

task ciclos;
    input integer n;
    begin
        repeat (n) @(posedge clk);
        #1;
    end
endtask

task checa_vazio;
    input [8*24-1:0] nome;
    begin
        if (n_wr !== n_esp) begin
            $display("FALHOU (%0s): %0d escritas, esperado %0d", nome, n_wr, n_esp);
            erros = erros + 1;
        end else if (mem_req !== 1'b0) begin
            $display("FALHOU (%0s): mem_req ainda ativo", nome);
            erros = erros + 1;
        end else begin
            $display("PASSOU: %0s", nome);
        end
    end
endtask

// ─── Testes ──────────────────────────────────────────────

initial begin
    $dumpfile("store_buffer.vcd");
    $dumpvars(0, store_buffer_tb);

    clk = 0; rst = 1;
    v = 3'b0; {dst1,dst2,dst3} = 9'b0;
    {dado1,dado2,dado3} = 96'b0;
    cv = 3'b0; {cr1,cr2,cr3} = 96'b0;

    @(posedge clk); #1;
    rst = 0;

    // ── Teste 1: 1 Store, só escreve depois do commit ──
    $display("\n=== TESTE 1: 1 Store ===");
    despacha(3'b001, 3'b100, 3'b000, 3'b000, 32'd100, 32'd0, 32'd0);
    ciclos(2);
    checa_vazio("sem escrita antes commit");
    espera_escrita(32'hAAAA0000, 32'd100);
    commita(3'b001, 32'hAAAA0000, 32'd0, 32'd0);
    ciclos(1);
    checa_vazio("1 Store");

    // ── Teste 2: ADD slot1 + Store slot2 ──
    $display("\n=== TESTE 2: ADD + Store ===");
    despacha(3'b011, 3'b000, 3'b100, 3'b000, 32'd0, 32'd200, 32'd0);
    espera_escrita(32'hBBBB0002, 32'd200);
    commita(3'b010, 32'd0, 32'hBBBB0002, 32'd0);
    ciclos(1);
    checa_vazio("ADD + Store");

    // ── Teste 3: Store + ADD + Store, commit no mesmo ciclo ──
    $display("\n=== TESTE 3: Store + ADD + Store ===");
    despacha(3'b111, 3'b100, 3'b000, 3'b100, 32'd300, 32'd0, 32'd400);
    espera_escrita(32'hCCCC0003, 32'd300);
    espera_escrita(32'hCCCC0005, 32'd400);
    commita(3'b101, 32'hCCCC0003, 32'd0, 32'hCCCC0005);
    ciclos(2);
    checa_vazio("Store + ADD + Store");

    // ── Teste 4: 3 Stores commitados no mesmo ciclo ──
    $display("\n=== TESTE 4: 3 Stores simultaneos ===");
    despacha(3'b111, 3'b100, 3'b100, 3'b100, 32'd500, 32'd600, 32'd700);
    espera_escrita(32'hDDDD0006, 32'd500);
    espera_escrita(32'hDDDD0007, 32'd600);
    espera_escrita(32'hDDDD0008, 32'd700);
    commita(3'b111, 32'hDDDD0006, 32'hDDDD0007, 32'hDDDD0008);
    ciclos(3);
    checa_vazio("3 Stores simultaneos");

    // ── Teste 5: commits em sequência, com escritas ainda pendentes ──
    $display("\n=== TESTE 5: commits seguidos ===");
    despacha(3'b111, 3'b100, 3'b100, 3'b100, 32'd800, 32'd900, 32'd1000);
    espera_escrita(32'hEEEE0009, 32'd800);
    espera_escrita(32'hEEEE0010, 32'd900);
    espera_escrita(32'hEEEE0011, 32'd1000);
    commita(3'b011, 32'hEEEE0009, 32'hEEEE0010, 32'd0);
    commita(3'b100, 32'd0, 32'd0, 32'hEEEE0011);
    ciclos(2);
    checa_vazio("commits seguidos");

    // ── Teste 6: enche até stop, sem commits ──
    $display("\n=== TESTE 6: Enchendo SB ate stop ===");
    begin : enche
        integer j;
        for (j = 0; j < 7; j = j + 1)
            despacha(3'b011, 3'b100, 3'b100, 3'b000, 32'd1000+j, 32'd2000+j, 32'd0);
    end
    if (stop !== 1'b1) begin
        $display("FALHOU (stop): 14 Stores pendentes e stop=%b", stop);
        erros = erros + 1;
    end else begin
        $display("PASSOU: stop com 14 Stores pendentes");
    end

    // ── Teste 7: Reset ──
    $display("\n=== TESTE 7: Reset ===");
    rst = 1;
    @(posedge clk); #1;
    rst = 0;
    if (stop !== 1'b0 || mem_req !== 1'b0 || U_sb.head !== 5'd0 ||
        U_sb.cptr !== 5'd0 || U_sb.tail !== 5'd0) begin
        $display("FALHOU (reset): stop=%b mem_req=%b head=%0d cptr=%0d tail=%0d",
            stop, mem_req, U_sb.head, U_sb.cptr, U_sb.tail);
        erros = erros + 1;
    end else begin
        $display("PASSOU: reset");
    end

    if (erros == 0)
        $display("\nTODOS OS TESTES PASSARAM");
    else
        $display("\n%0d ERRO(S)", erros);
    #20;
    $finish;
end

endmodule
