`timescale 1ns/1ps

// Testbench do processador completo com o programa_02 (ordem entre loads e stores).
// Alem dos resultados finais, um monitor independente da implementacao acompanha
// cada Store do despacho ate a escrita e acusa:
//   - Load acessando a memoria com Store mais antigo de endereco igual ou desconhecido
//   - forwarding indevido ou com dado diferente do Store mais novo que coincide
//   - escrita na memoria fora de ordem ou com endereco/dado errado
module tb_processador;
    parameter ARQUIVO = "programa_02";
    parameter CICLOS  = 200;

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    processador dut (.clk(clk), .rst(rst));

    integer erros = 0;
    integer i, k;

    // ─── Monitor de Stores ───────────────────────────────
    // Fila em ordem de programa: [st_ini, st_fim)
    reg [4:0]  st_rob  [0:255];
    reg [31:0] st_addr [0:255];
    reg [31:0] st_dado [0:255];
    reg        st_ok   [0:255];   // endereco ja calculado pelo caminho
    integer st_ini = 0, st_fim = 0, st_cptr = 0;
    integer n_wb, idade_load, idade_store;
    integer n_fwd = 0;            // Loads resolvidos por forwarding
    reg        fwd_ok;
    reg [31:0] fwd_dado;

    always @(posedge clk) begin
        if (!rst) begin
            // As checagens dos Loads vem antes de retirar o Store escrito neste ciclo:
            // a escrita so acontece na borda, entao ele ainda conta como pendente

            // Load acessando a memoria: nenhum Store mais antigo pode ter endereco igual ou desconhecido
            if (dut.load_grant) begin
                idade_load = (dut.lrid - dut.rob_u.head[4:0]) & 31;
                for (k = st_ini; k < st_fim; k = k + 1) begin
                    idade_store = (st_rob[k] - dut.rob_u.head[4:0]) & 31;
                    // Commitados sao sempre mais antigos; os demais, pela distancia ao head do ROB
                    if (k < st_cptr || idade_store < idade_load) begin
                        if (!st_ok[k]) begin
                            $display("ERRO t=%0t: load rob_id=%0d leu mem[%0d] com Store mais antigo (rob_id=%0d) sem endereco",
                                $time, dut.lrid, dut.laddr, st_rob[k]);
                            erros = erros + 1;
                        end else if (st_addr[k] == dut.laddr) begin
                            $display("ERRO t=%0t: load rob_id=%0d leu mem[%0d] antes do Store mais antigo (rob_id=%0d) no mesmo endereco",
                                $time, dut.lrid, dut.laddr, st_rob[k]);
                            erros = erros + 1;
                        end
                    end
                end
            end

            // Forwarding: o dado deve ser o do Store mais novo, entre os mais antigos que o
            // Load, no mesmo endereco, sem Store de endereco desconhecido depois dele
            if (dut.lbuf.fwd) begin
                n_fwd = n_fwd + 1;
                idade_load = (dut.lrid - dut.rob_u.head[4:0]) & 31;
                fwd_ok = 1'b0; fwd_dado = 32'bx;
                for (k = st_ini; k < st_fim; k = k + 1) begin
                    idade_store = (st_rob[k] - dut.rob_u.head[4:0]) & 31;
                    if (k < st_cptr || idade_store < idade_load) begin
                        if (!st_ok[k]) begin
                            fwd_ok = 1'b0;
                        end else if (st_addr[k] == dut.laddr) begin
                            fwd_ok = 1'b1; fwd_dado = st_dado[k];
                        end
                    end
                end
                if (!fwd_ok) begin
                    $display("ERRO t=%0t: forwarding indevido para load rob_id=%0d mem[%0d]",
                        $time, dut.lrid, dut.laddr);
                    erros = erros + 1;
                end else if (dut.lbuf.dado_lido !== fwd_dado) begin
                    $display("ERRO t=%0t: forwarding para load rob_id=%0d mem[%0d] entregou %h, esperado %h",
                        $time, dut.lrid, dut.laddr, dut.lbuf.dado_lido, fwd_dado);
                    erros = erros + 1;
                end
            end

            // Escrita na memoria: deve ser o Store mais antigo, com endereco e dado certos
            if (dut.sb_mem_req) begin
                if (st_ini >= st_cptr) begin
                    $display("ERRO t=%0t: escrita de Store nao commitado (addr=%0d)", $time, dut.sb_mem_addr);
                    erros = erros + 1;
                end else if (dut.sb_mem_addr !== st_addr[st_ini] || dut.sb_mem_dado !== st_dado[st_ini]) begin
                    $display("ERRO t=%0t: escrita mem[%0d]=%h, esperado mem[%0d]=%h",
                        $time, dut.sb_mem_addr, dut.sb_mem_dado, st_addr[st_ini], st_dado[st_ini]);
                    erros = erros + 1;
                end
                st_ini = st_ini + 1;
            end

            // Commit: os Stores commitados sao os mais antigos ainda nao commitados
            n_wb = dut.cv_store[0] + dut.cv_store[1] + dut.cv_store[2];
            st_cptr = st_cptr + n_wb;

            // Endereco calculado pelos caminhos
            for (k = st_cptr; k < st_fim; k = k + 1) begin
                if (dut.wb1 && dut.rid1 == st_rob[k]) begin st_addr[k] = dut.r1; st_ok[k] = 1'b1; end
                if (dut.wb2 && dut.rid2 == st_rob[k]) begin st_addr[k] = dut.r2; st_ok[k] = 1'b1; end
            end

            // Despacho, na ordem dos slots
            if (dut.disp_v[0] && dut.disp_dst1 == 3'b100) begin
                st_rob[st_fim] = dut.rob_id1; st_dado[st_fim] = dut.disp_dado1; st_ok[st_fim] = 1'b0;
                st_fim = st_fim + 1;
            end
            if (dut.disp_v[1] && dut.disp_dst2 == 3'b100) begin
                st_rob[st_fim] = dut.rob_id2; st_dado[st_fim] = dut.disp_dado2; st_ok[st_fim] = 1'b0;
                st_fim = st_fim + 1;
            end
            if (dut.disp_v[2] && dut.disp_dst3 == 3'b100) begin
                st_rob[st_fim] = dut.rob_id3; st_dado[st_fim] = dut.disp_dado3; st_ok[st_fim] = 1'b0;
                st_fim = st_fim + 1;
            end
        end
    end

    // ─── Verificacao final ───────────────────────────────
    task checa_reg;
        input [4:0]  r;
        input [31:0] esperado;
        input [8*40-1:0] nome;
        begin
            if (dut.banco.registradores[r] !== esperado) begin
                $display("FALHOU (%0s): x%0d = %h, esperado %h", nome, r, dut.banco.registradores[r], esperado);
                erros = erros + 1;
            end else begin
                $display("PASSOU: %0s (x%0d = %h)", nome, r, esperado);
            end
        end
    endtask

    task checa_mem;
        input [31:0] a;
        input [31:0] esperado;
        input [8*40-1:0] nome;
        reg   [31:0] lido;
        begin
            lido = {dut.med.memoria[a+3], dut.med.memoria[a+2], dut.med.memoria[a+1], dut.med.memoria[a]};
            if (lido !== esperado) begin
                $display("FALHOU (%0s): mem[%0d] = %h, esperado %h", nome, a, lido, esperado);
                erros = erros + 1;
            end else begin
                $display("PASSOU: %0s (mem[%0d] = %h)", nome, a, esperado);
            end
        end
    endtask

    initial begin
        $readmemh(ARQUIVO, dut.mei.memoria);
        for (i = 0; i < 2048; i = i + 1)
            dut.med.memoria[i] = i[7:0];

        repeat (2) @(posedge clk);
        #1 rst = 0;
        repeat (CICLOS) @(posedge clk);
        #1;

        $display("\n=== Resultados ===");
        checa_reg(5'd5,  32'h03020100, "A: load antigo");
        checa_reg(5'd6,  32'h00000077, "A: load apos store atrasado");
        checa_reg(5'd7,  32'h27262524, "B: enderecos diferentes");
        checa_reg(5'd8,  32'h00000055, "C: store seguido de load");
        checa_reg(5'd9,  32'h00000055, "D: load antes de store");
        checa_reg(5'd10, 32'h00000055, "E: dois stores, load le o novo");
        checa_mem(32'd16, 32'h00000055, "memoria apos A e C");
        checa_mem(32'd32, 32'h00000077, "memoria apos B e D");
        checa_mem(32'd8,  32'h00000055, "memoria apos E");

        if (n_fwd == 0) begin
            $display("FALHOU: nenhum load foi resolvido por forwarding");
            erros = erros + 1;
        end else begin
            $display("PASSOU: %0d load(s) resolvido(s) por forwarding", n_fwd);
        end

        if (st_ini != st_fim) begin
            $display("FALHOU: %0d Store(s) nao escrito(s) na memoria", st_fim - st_ini);
            erros = erros + 1;
        end

        if (erros == 0)
            $display("\nTODOS OS TESTES PASSARAM");
        else
            $display("\n%0d ERRO(S)", erros);
        $finish;
    end
endmodule
