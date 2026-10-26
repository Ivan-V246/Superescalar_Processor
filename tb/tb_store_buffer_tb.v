module store_buffer_tb();

reg clk, rst;

reg [2:0]  v;
reg [2:0]  dst1, dst2, dst3;
reg [4:0]  rob_id1, rob_id2, rob_id3;
reg [31:0] dado1, dado2, dado3;

reg [2:0]  wb;
reg [4:0]  rid1, rid2, rid3;
reg [31:0] r1, r2, r3;

reg [2:0]  cv;

reg [4:0]  q_idade;
reg [31:0] q_addr;

wire [4:0]  sb_tail;
wire        q_espera;
wire        q_hit;
wire [31:0] q_dado;
wire        mem_req;
wire [31:0] mem_addr;
wire [31:0] mem_dado;
wire        stop;

integer erros = 0;

store_buffer U_sb (
    .clk(clk), .rst(rst),
    .v(v),
    .dst1(dst1), .dst2(dst2), .dst3(dst3),
    .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
    .dado1(dado1), .dado2(dado2), .dado3(dado3),
    .wb(wb),
    .rid1(rid1), .rid2(rid2), .rid3(rid3),
    .r1(r1), .r2(r2), .r3(r3),
    .cv(cv),
    .sb_tail(sb_tail), .q_idade(q_idade), .q_addr(q_addr), .q_espera(q_espera),
    .q_hit(q_hit), .q_dado(q_dado),
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
    input [4:0]  _rob_id1, _rob_id2, _rob_id3;
    input [31:0] _dado1, _dado2, _dado3;
    begin
        v = _v; dst1 = _dst1; dst2 = _dst2; dst3 = _dst3;
        rob_id1 = _rob_id1; rob_id2 = _rob_id2; rob_id3 = _rob_id3;
        dado1 = _dado1; dado2 = _dado2; dado3 = _dado3;
        @(posedge clk); #1;
        v = 3'b0;
    end
endtask

// Caminhos entregando o endereço dos Stores
task resolve;
    input [2:0]  _wb;
    input [4:0]  _rid1, _rid2, _rid3;
    input [31:0] _r1, _r2, _r3;
    begin
        wb = _wb; rid1 = _rid1; rid2 = _rid2; rid3 = _rid3;
        r1 = _r1; r2 = _r2; r3 = _r3;
        @(posedge clk); #1;
        wb = 3'b0;
    end
endtask

task commita;
    input [2:0] _cv;
    begin
        cv = _cv;
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
    input [8*32-1:0] nome;
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

// Consulta de um Load com a idade e o endereço dados.
// Respostas: MEM (lê a memória), ESPERA, ou FWD (forwarding com o dado dado)
localparam MEM = 2'd0, ESPERA = 2'd1, FWD = 2'd2;

task consulta;
    input [4:0]  _idade;
    input [31:0] _addr;
    input [1:0]  esperado;
    input [31:0] esp_dado;
    input [8*44-1:0] nome;
    reg   [1:0]  obtido;
    begin
        q_idade = _idade; q_addr = _addr;
        #1;
        obtido = q_espera ? ESPERA : (q_hit ? FWD : MEM);
        if (obtido !== esperado) begin
            $display("FALHOU (%0s): q_espera=%b q_hit=%b, esperado %0s", nome, q_espera, q_hit,
                esperado == MEM ? "MEM" : (esperado == ESPERA ? "ESPERA" : "FWD"));
            erros = erros + 1;
        end else if (esperado == FWD && q_dado !== esp_dado) begin
            $display("FALHOU (%0s): q_dado=%0d, esperado %0d", nome, q_dado, esp_dado);
            erros = erros + 1;
        end else if (obtido == FWD) begin
            $display("PASSOU: %0s (FWD dado=%0d)", nome, q_dado);
        end else begin
            $display("PASSOU: %0s (%0s)", nome, obtido == MEM ? "MEM" : "ESPERA");
        end
    end
endtask

// ─── Testes ──────────────────────────────────────────────
integer t0;

initial begin
    $dumpfile("store_buffer.vcd");
    $dumpvars(0, store_buffer_tb);

    clk = 0; rst = 1;
    v = 3'b0; {dst1,dst2,dst3} = 9'b0;
    {rob_id1,rob_id2,rob_id3} = 15'b0;
    {dado1,dado2,dado3} = 96'b0;
    wb = 3'b0; {rid1,rid2,rid3} = 15'b0; {r1,r2,r3} = 96'b0;
    cv = 3'b0;
    q_idade = 5'd0; q_addr = 32'd0;

    @(posedge clk); #1;
    rst = 0;

    // ── Teste 1: 1 Store, só escreve depois do commit ──
    $display("\n=== TESTE 1: 1 Store ===");
    despacha(3'b001, 3'b100, 3'b000, 3'b000, 5'd0, 5'd0, 5'd0, 32'd100, 32'd0, 32'd0);
    resolve(3'b001, 5'd0, 5'd0, 5'd0, 32'hAAAA0000, 32'd0, 32'd0);
    ciclos(2);
    checa_vazio("sem escrita antes do commit");
    espera_escrita(32'hAAAA0000, 32'd100);
    commita(3'b001);
    ciclos(1);
    checa_vazio("1 Store");

    // ── Teste 2: ADD slot1 + Store slot2 ──
    $display("\n=== TESTE 2: ADD + Store ===");
    despacha(3'b011, 3'b000, 3'b100, 3'b000, 5'd1, 5'd2, 5'd0, 32'd0, 32'd200, 32'd0);
    resolve(3'b011, 5'd1, 5'd2, 5'd0, 32'd12345, 32'hBBBB0002, 32'd0);
    espera_escrita(32'hBBBB0002, 32'd200);
    commita(3'b010);
    ciclos(1);
    checa_vazio("ADD + Store");

    // ── Teste 3: Store + ADD + Store, commit no mesmo ciclo ──
    $display("\n=== TESTE 3: Store + ADD + Store ===");
    despacha(3'b111, 3'b100, 3'b000, 3'b100, 5'd3, 5'd4, 5'd5, 32'd300, 32'd0, 32'd400);
    resolve(3'b011, 5'd5, 5'd3, 5'd0, 32'hCCCC0005, 32'hCCCC0003, 32'd0);  // fora de ordem
    espera_escrita(32'hCCCC0003, 32'd300);
    espera_escrita(32'hCCCC0005, 32'd400);
    commita(3'b101);
    ciclos(2);
    checa_vazio("Store + ADD + Store");

    // ── Teste 4: 3 Stores commitados no mesmo ciclo ──
    $display("\n=== TESTE 4: 3 Stores simultaneos ===");
    despacha(3'b111, 3'b100, 3'b100, 3'b100, 5'd6, 5'd7, 5'd8, 32'd500, 32'd600, 32'd700);
    resolve(3'b111, 5'd6, 5'd7, 5'd8, 32'hDDDD0006, 32'hDDDD0007, 32'hDDDD0008);
    espera_escrita(32'hDDDD0006, 32'd500);
    espera_escrita(32'hDDDD0007, 32'd600);
    espera_escrita(32'hDDDD0008, 32'd700);
    commita(3'b111);
    ciclos(3);
    checa_vazio("3 Stores simultaneos");

    // ── Teste 5: rob_id reutilizado não sobrescreve Store já commitado ──
    // Os 3 Stores são commitados juntos; enquanto o 3º espera a escrita,
    // um caminho entrega um resultado com o mesmo rob_id (instrução nova no ROB)
    $display("\n=== TESTE 5: rob_id reutilizado ===");
    despacha(3'b111, 3'b100, 3'b100, 3'b100, 5'd9, 5'd10, 5'd11, 32'd800, 32'd900, 32'd1000);
    resolve(3'b111, 5'd9, 5'd10, 5'd11, 32'hEEEE0009, 32'hEEEE0010, 32'hEEEE0011);
    espera_escrita(32'hEEEE0009, 32'd800);
    espera_escrita(32'hEEEE0010, 32'd900);
    espera_escrita(32'hEEEE0011, 32'd1000);
    commita(3'b111);
    resolve(3'b001, 5'd11, 5'd0, 5'd0, 32'hBAD00000, 32'd0, 32'd0);
    ciclos(2);
    checa_vazio("rob_id reutilizado");

    // ── Teste 6: consulta de Loads ──
    // Stores em [head, tail): S0 (rob 12, endereço 0x100) e S1 (rob 13, endereço desconhecido)
    $display("\n=== TESTE 6: consulta ===");
    t0 = sb_tail;
    consulta(t0, 32'h100, MEM, 0, "sem Stores mais antigos");
    despacha(3'b011, 3'b100, 3'b100, 3'b000, 5'd12, 5'd13, 5'd0, 32'd11, 32'd22, 32'd0);
    consulta(t0,     32'h100, MEM,    0,  "Stores mais novos que o Load");
    consulta(t0 + 1, 32'h100, ESPERA, 0,  "S0 mais antigo, endereco desconhecido");
    resolve(3'b001, 5'd12, 5'd0, 5'd0, 32'h100, 32'd0, 32'd0);
    consulta(t0 + 1, 32'h100, FWD,    11, "S0 mais antigo, mesmo endereco");
    consulta(t0 + 1, 32'h200, MEM,    0,  "S0 mais antigo, endereco diferente");
    consulta(t0 + 2, 32'h200, ESPERA, 0,  "S1 mais antigo, endereco desconhecido");
    resolve(3'b001, 5'd13, 5'd0, 5'd0, 32'h300, 32'd0, 32'd0);
    consulta(t0 + 2, 32'h200, MEM,    0,  "S0 e S1 conhecidos e diferentes");
    consulta(t0 + 2, 32'h300, FWD,    22, "S1 mais antigo, mesmo endereco");
    consulta(t0 + 2, 32'h100, FWD,    11, "S0 coincide, S1 conhecido e diferente");

    // Commit dos dois: S0 é escrito no próximo ciclo e S1 no seguinte.
    // Enquanto S1 não é escrito, ele ainda bloqueia o Load
    espera_escrita(32'h100, 32'd11);
    espera_escrita(32'h300, 32'd22);
    commita(3'b011);
    ciclos(1);
    consulta(t0 + 2, 32'h300, FWD,    22, "S1 commitado, ainda nao escrito");
    ciclos(1);
    consulta(t0 + 2, 32'h300, MEM,    0,  "S1 ja escrito");
    checa_vazio("escritas do teste 6");

    // ── Teste 6b: prioridade entre Stores ──
    // S2, S3 e S4 (rob 14, 15, 16), todos para 0x400 quando resolvidos
    $display("\n=== TESTE 6b: prioridade ===");
    t0 = sb_tail;
    despacha(3'b111, 3'b100, 3'b100, 3'b100, 5'd14, 5'd15, 5'd16, 32'd33, 32'd44, 32'd55);
    resolve(3'b001, 5'd15, 5'd0, 5'd0, 32'h400, 32'd0, 32'd0);
    consulta(t0 + 2, 32'h400, FWD,    44, "desconhecido antes do que coincide");
    consulta(t0 + 3, 32'h400, ESPERA, 0,  "desconhecido depois do que coincide");
    resolve(3'b001, 5'd16, 5'd0, 5'd0, 32'h400, 32'd0, 32'd0);
    consulta(t0 + 3, 32'h400, FWD,    55, "dois coincidem: vale o mais novo");
    resolve(3'b001, 5'd14, 5'd0, 5'd0, 32'h400, 32'd0, 32'd0);
    consulta(t0 + 3, 32'h400, FWD,    55, "tres coincidem: vale o mais novo");
    consulta(t0 + 1, 32'h400, FWD,    33, "so o mais antigo e anterior ao Load");
    espera_escrita(32'h400, 32'd33);
    espera_escrita(32'h400, 32'd44);
    espera_escrita(32'h400, 32'd55);
    commita(3'b111);
    ciclos(3);
    checa_vazio("escritas do teste 6b");

    // ── Teste 7: enche até stop, sem commits ──
    $display("\n=== TESTE 7: Enchendo SB ate stop ===");
    begin : enche
        integer j;
        for (j = 0; j < 7; j = j + 1)
            despacha(3'b011, 3'b100, 3'b100, 3'b000, 5'd17+j*2, 5'd18+j*2, 5'd0,
                     32'd1000+j, 32'd2000+j, 32'd0);
    end
    if (stop !== 1'b1) begin
        $display("FALHOU (stop): 14 Stores pendentes e stop=%b", stop);
        erros = erros + 1;
    end else begin
        $display("PASSOU: stop com 14 Stores pendentes");
    end

    // ── Teste 8: Reset ──
    $display("\n=== TESTE 8: Reset ===");
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
