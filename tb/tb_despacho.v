`timescale 1ns/1ps

//Testbench do despacho fora de ordem.
//O ROB e a unidade de hazard são simulados aqui: o Rob_tail avança com as alocações
//e o vetor "pronto" é controlado por cada teste.
module tb_despacho;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    reg  [2:0]  mei_valid = 0;
    reg  [31:0] mei_instr0 = 0, mei_instr1 = 0, mei_instr2 = 0;
    reg  [9:0]  mei_pc0 = 0, mei_pc1 = 0, mei_pc2 = 0;
    reg         mei_previu0 = 0, mei_previu1 = 0, mei_previu2 = 0;
    reg  [9:0]  mei_alvo0 = 0, mei_alvo1 = 0, mei_alvo2 = 0;
    wire        mei_stop, pc_advence;
    wire [4:0]  ocupacao;

    reg         stop = 0, load_buffer_stop = 0, store_buffer_stop = 0;
    reg  [4:0]  Rob_tail = 0, sb_tail = 0, lb_tail = 0;
    wire [2:0]  v, dst1, dst2, dst3;
    wire [4:0]  rd1, rd2, rd3, rob_id1, rob_id2, rob_id3;
    wire [4:0]  al_rs1_0, al_rs1_1, al_rs1_2, al_rs2_0, al_rs2_1, al_rs2_2;
    wire        al_escreve0, al_escreve1, al_escreve2, al_alu0, al_alu1, al_alu2;
    wire        al_desvio0, al_desvio1, al_desvio2;

    reg  [31:0] pronto = 32'hFFFFFFFF;
    reg  [2:0]  ck_livres = 3'd4;
    reg         flush_ok = 0;
    reg  [4:0]  flush_rob_id = 0, rob_head = 0;

    wire        p1v, p2v, p3v;
    wire [31:0] p1i, p2i, p3i, p1imm, p2imm, p3imm;
    wire [4:0]  p1rob, p2rob, p3rob, p1rs1, p1rs2, p2rs1, p2rs2, p3rs1, p3rs2;
    wire [3:0]  p1op, p2op;
    wire [9:0]  p1pc, p2pc, p3pc, p3alvo;
    wire        p3prev;
    wire        st1v, st2v;
    wire [4:0]  st1rob, st2rob;
    wire [31:0] st1d, st2d;

    despacho dut (
        .clk(clk), .rst(rst),
        .mei_valid(mei_valid), .mei_instr0(mei_instr0), .mei_instr1(mei_instr1), .mei_instr2(mei_instr2),
        .mei_ordem0(32'd0), .mei_ordem1(32'd1), .mei_ordem2(32'd2),
        .mei_pc0(mei_pc0), .mei_pc1(mei_pc1), .mei_pc2(mei_pc2),
        .mei_previu0(mei_previu0), .mei_previu1(mei_previu1), .mei_previu2(mei_previu2),
        .mei_alvo0(mei_alvo0), .mei_alvo1(mei_alvo1), .mei_alvo2(mei_alvo2),
        .mei_stop(mei_stop), .pc_advence(pc_advence), .ocupacao(ocupacao),
        .stop(stop), .Rob_tail(Rob_tail), .load_buffer_stop(load_buffer_stop), .store_buffer_stop(store_buffer_stop),
        .sb_tail(sb_tail), .lb_tail(lb_tail),
        .v(v), .dst1(dst1), .dst2(dst2), .dst3(dst3), .rd1(rd1), .rd2(rd2), .rd3(rd3),
        .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3), .dado1(), .dado2(), .dado3(),
        .al_rs1_0(al_rs1_0), .al_rs1_1(al_rs1_1), .al_rs1_2(al_rs1_2),
        .al_rs2_0(al_rs2_0), .al_rs2_1(al_rs2_1), .al_rs2_2(al_rs2_2),
        .al_escreve0(al_escreve0), .al_escreve1(al_escreve1), .al_escreve2(al_escreve2),
        .al_alu0(al_alu0), .al_alu1(al_alu1), .al_alu2(al_alu2),
        .al_desvio0(al_desvio0), .al_desvio1(al_desvio1), .al_desvio2(al_desvio2),
        .pronto(pronto), .ck_livres(ck_livres), .flush_ok(flush_ok), .flush_rob_id(flush_rob_id), .rob_head(rob_head),
        .path1_ready(1'b1), .path2_ready(1'b1),
        .path1_valid(p1v), .path2_valid(p2v), .path1_instr(p1i), .path2_instr(p2i),
        .path1_ordem(), .path2_ordem(), .path1_pc(p1pc), .path2_pc(p2pc),
        .path1_rs1_addr(p1rs1), .path1_rs2_addr(p1rs2), .path2_rs1_addr(p2rs1), .path2_rs2_addr(p2rs2),
        .path1_rob_id(p1rob), .path2_rob_id(p2rob),
        .path1_previu(), .path2_previu(), .path1_alvo(), .path2_alvo(),
        .path1_sb_tail(), .path2_sb_tail(), .path1_lb_tail(), .path2_lb_tail(),
        .path1_alu_op(p1op), .path2_alu_op(p2op), .path1_imm(p1imm), .path2_imm(p2imm),
        .path1_rs1_data(32'd11), .path1_rs2_data(32'd22), .path2_rs1_data(32'd33), .path2_rs2_data(32'd44),
        .store1_valid(st1v), .store2_valid(st2v), .store1_rob_id(st1rob), .store2_rob_id(st2rob),
        .store1_dado(st1d), .store2_dado(st2d),
        .path3_ready(1'b1), .path3_valid(p3v), .path3_instr(p3i), .path3_ordem(), .path3_pc(p3pc),
        .path3_rs1_addr(p3rs1), .path3_rs2_addr(p3rs2), .path3_rob_id(p3rob),
        .path3_previu(p3prev), .path3_alvo(p3alvo), .path3_sb_tail(), .path3_lb_tail(), .path3_imm(p3imm)
    );

    //ROB simulado: o tail avança com as alocações e volta no descarte
    always @(posedge clk)
        if (rst) Rob_tail <= 0;
        else if (flush_ok) Rob_tail <= flush_rob_id + 5'd1;
        else Rob_tail <= Rob_tail + v[0] + v[1] + v[2];

    //Instruções
    function [31:0] ADD(input [4:0] rd, rs1, rs2); ADD = {7'd0, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
    function [31:0] SUB(input [4:0] rd, rs1, rs2); SUB = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011}; endfunction
    function [31:0] ADDI(input [4:0] rd, rs1, input [11:0] im); ADDI = {im, rs1, 3'b000, rd, 7'b0010011}; endfunction
    function [31:0] LW(input [4:0] rd, rs1); LW = {12'd0, rs1, 3'b010, rd, 7'b0000011}; endfunction
    function [31:0] SW(input [4:0] rs2, rs1); SW = {7'd0, rs2, rs1, 3'b010, 5'd0, 7'b0100011}; endfunction
    function [31:0] BEQ(input [4:0] rs1, rs2); BEQ = {1'b0, 6'd0, rs2, rs1, 3'b000, 4'b0100, 1'b0, 7'b1100011}; endfunction
    localparam [31:0] ECALL = 32'h00000073, NOP = 32'h00000013;

    integer erros = 0;
    task falha(input [8*60-1:0] msg);
        begin $display("FALHOU: %0s (t=%0t)", msg, $time); erros = erros + 1; end
    endtask

    task reinicia;
        begin
            @(negedge clk); rst = 1; pronto = 32'hFFFFFFFF; flush_ok = 0; mei_valid = 0;
            @(negedge clk); @(negedge clk); rst = 0;
        end
    endtask

    //Coloca um grupo na entrada; as instruções ficam na fila após a borda
    task entra(input [2:0] val, input [31:0] i0, i1, i2);
        begin
            @(negedge clk);
            mei_valid = val; mei_instr0 = i0; mei_instr1 = i1; mei_instr2 = i2;
            mei_pc0 = 10'd100; mei_pc1 = 10'd104; mei_pc2 = 10'd108;
            @(posedge clk); #1;
            mei_valid = 0; #1;
        end
    endtask

    integer k, esperado;
    initial begin
        $display("INICIO DOS TESTES DO DESPACHO");
        reinicia;

        //1) Alocação na entrada
        @(negedge clk);
        mei_valid = 3'b111; mei_instr0 = ADD(5'd3, 5'd1, 5'd2); mei_instr1 = LW(5'd4, 5'd3); mei_instr2 = BEQ(5'd4, 5'd5);
        #1;
        if (v !== 3'b111 || rob_id1 !== 0 || rob_id2 !== 1 || rob_id3 !== 2) falha("alocacao: v/rob_id");
        if (dst1 !== 3'b000 || dst2 !== 3'b010 || rd1 !== 3 || rd2 !== 4 || rd3 !== 0) falha("alocacao: dst/rd");
        if (al_rs1_0 !== 1 || al_rs2_0 !== 2 || al_rs1_1 !== 3 || al_rs2_1 !== 0) falha("alocacao: registradores lidos");
        if (!al_escreve0 || !al_escreve1 || al_escreve2) falha("alocacao: escreve");
        if (!al_alu0 || al_alu1 || !al_desvio2 || al_desvio0) falha("alocacao: alu/desvio");
        if (!pc_advence) falha("alocacao: pc_advence");
        @(posedge clk); #1; mei_valid = 0; #1;
        //Tudo pronto: ADD e LW nos caminhos 1 e 2, BEQ no 3
        if (!p1v || p1rob !== 0 || !p2v || p2rob !== 1 || !p3v || p3rob !== 2) falha("envio do trio");
        if (p1rs1 !== 1 || p1rs2 !== 2 || p3rs1 !== 4 || p3rs2 !== 5 || p3imm !== 32'd8) falha("campos enviados");
        @(posedge clk); #1;
        if (ocupacao !== 0) falha("fila deveria esvaziar");
        $display("PASSOU: alocacao e envio de ADD, LW e BEQ");

        //2) Fora de ordem: a mais antiga espera, as seguintes passam
        reinicia;
        pronto = ~32'd1;   //rob 0 nao pronto
        entra(3'b111, ADD(5'd1, 5'd9, 5'd9), ADD(5'd2, 5'd8, 5'd8), ADDI(5'd3, 5'd0, 12'd5));
        if (!p1v || p1rob !== 1 || !p2v || p2rob !== 2) falha("ULA mais novas nao passaram na frente");
        @(posedge clk); #1;
        if (dut.cnt_fora_de_ordem !== 2) falha("contador fora_de_ordem");
        if (p1v || p2v) falha("enviou a nao pronta");
        pronto = 32'hFFFFFFFF; #1;
        if (!p1v || p1rob !== 0) falha("a antiga nao saiu depois de pronta");
        @(posedge clk); #1;
        if (ocupacao !== 0) falha("fila deveria esvaziar (buracos)");
        $display("PASSOU: instrucoes de ULA passam na frente");

        //3) Memória em ordem entre si: o store nao passa o load que espera; a ULA passa
        reinicia;
        pronto = ~32'd1;   //o load (rob 0) espera
        entra(3'b111, LW(5'd1, 5'd9), SW(5'd2, 5'd8), ADDI(5'd3, 5'd0, 12'd1));
        if (!p1v || p1rob !== 2 || p2v) falha("so a ADDI deveria sair");
        @(posedge clk); #1;
        pronto = 32'hFFFFFFFF; #1;
        if (!p1v || p1rob !== 0 || !p2v || p2rob !== 1) falha("LW e SW deveriam sair em ordem");
        if (!st2v || st2rob !== 1 || st2d !== 32'd44) falha("dado do store");
        @(posedge clk); #1;
        $display("PASSOU: loads e stores em ordem entre si");

        //4) Desvios em ordem entre si; ULA passa o desvio que espera
        reinicia;
        pronto = ~32'd1;   //o primeiro BEQ (rob 0) espera
        entra(3'b111, BEQ(5'd1, 5'd2), BEQ(5'd3, 5'd4), ADD(5'd5, 5'd6, 5'd7));
        if (p3v) falha("o segundo desvio passou o primeiro");
        if (!p1v || p1rob !== 2) falha("a ADD deveria passar os desvios");
        @(posedge clk); #1;
        pronto = 32'hFFFFFFFF; #1;
        if (!p3v || p3rob !== 0) falha("primeiro desvio");
        @(posedge clk); #1;
        if (!p3v || p3rob !== 1) falha("segundo desvio");
        @(posedge clk); #1;
        $display("PASSOU: desvios em ordem entre si");

        //5) Parada: nada mais novo sai
        reinicia;
        entra(3'b111, ADD(5'd1, 5'd2, 5'd3), ECALL, ADD(5'd4, 5'd2, 5'd3));
        if (!p1v || p1rob !== 0 || p2v) falha("so a ADD antes do ECALL sai");
        @(posedge clk); #1;
        for (k = 0; k < 3; k = k + 1) begin
            if (p1v || p2v || p3v) falha("enviou depois do ECALL");
            @(posedge clk); #1;
        end
        if (dut.cnt_parado_fim < 3) falha("contador parado_fim");
        $display("PASSOU: parada segura as mais novas");

        //6) Descarte: remove so as mais novas que o desvio, mesmo com envio fora de ordem
        reinicia;
        pronto = ~32'd5;   //rob 0 e 2 esperam; o BEQ (rob 1) sai antes
        entra(3'b111, ADD(5'd1, 5'd9, 5'd9), BEQ(5'd1, 5'd2), ADD(5'd3, 5'd9, 5'd9));
        if (!p3v || p3rob !== 1 || p1v) falha("o BEQ deveria sair sozinho");
        @(posedge clk); #1;
        //O BEQ errou: chega o descarte, com um grupo novo na entrada
        @(negedge clk);
        flush_ok = 1; flush_rob_id = 1; rob_head = 0; pronto = 32'hFFFFFFFF;
        mei_valid = 3'b111; mei_instr0 = NOP; mei_instr1 = NOP; mei_instr2 = NOP;
        #1;
        if (p1v || p2v || p3v) falha("enviou no ciclo do descarte");
        if (v !== 0 || pc_advence) falha("alocou no ciclo do descarte");
        @(posedge clk); #1;
        flush_ok = 0; mei_valid = 0; #1;
        if (ocupacao !== 2) falha("deveria manter a posicao da ADD antiga (e o buraco do BEQ)");
        if (!p1v || p1rob !== 0 || p2v) falha("so a ADD mais antiga que o desvio deveria restar");
        @(posedge clk); #1;
        if (ocupacao !== 0) falha("fila deveria esvaziar apos o descarte");
        $display("PASSOU: descarte remove so as mais novas que o desvio");

        //7) Fila cheia (16 posições) e esvaziamento em ordem
        reinicia;
        pronto = 32'd0;
        for (k = 0; k < 4; k = k + 1) entra(3'b111, NOP, NOP, NOP);
        entra(3'b001, NOP, NOP, NOP);
        if (ocupacao !== 13) falha("ocupacao 13");
        entra(3'b111, NOP, NOP, NOP);
        if (ocupacao !== 16) falha("ocupacao 16 (cheia)");
        if (!mei_stop) falha("mei_stop com a fila cheia");
        pronto = 32'hFFFFFFFF; #1;
        esperado = 0;
        for (k = 0; k < 8; k = k + 1) begin
            if (!p1v || p1rob !== esperado || !p2v || p2rob !== esperado + 1) falha("ordem de saida da fila cheia");
            esperado = esperado + 2;
            @(posedge clk); #1;
        end
        if (ocupacao !== 0) falha("fila cheia deveria esvaziar");
        $display("PASSOU: fila cheia (16 posicoes)");

        //8) Bloqueio de entrada pelo load buffer
        reinicia;
        @(negedge clk);
        load_buffer_stop = 1; mei_valid = 3'b001; mei_instr0 = LW(5'd1, 5'd2); #1;
        if (v !== 0 || pc_advence) falha("load alocado com o load buffer cheio");
        @(posedge clk); #1;
        if (dut.cnt_entrada_bloqueada !== 1) falha("contador entrada_bloqueada");
        load_buffer_stop = 0; mei_valid = 0;
        $display("PASSOU: bloqueio de entrada e contador");


        //9) Sem copia livre na unidade de hazard, um grupo com desvio nao entra
        reinicia;
        @(negedge clk);
        ck_livres = 3'd1; mei_valid = 3'b111;
        mei_instr0 = BEQ(5'd1, 5'd2); mei_instr1 = BEQ(5'd3, 5'd4); mei_instr2 = NOP; #1;
        if (v !== 0 || pc_advence) falha("grupo com 2 desvios entrou com 1 copia livre");
        ck_livres = 3'd2; #1;
        if (v !== 3'b111 || !pc_advence) falha("grupo deveria entrar com 2 copias livres");
        @(posedge clk); #1; mei_valid = 0; ck_livres = 3'd4;
        if (dut.cnt_sem_copia !== 0) falha("contador sem_copia nao deveria contar o ciclo aceito");
        $display("PASSOU: espera por copia livre para desvios");

        if (erros == 0) $display("TODOS OS TESTES PASSARAM");
        else $display("%0d ERRO(S)", erros);
        $finish;
    end

    initial begin #20000; $display("FALHOU: timeout"); $finish; end
endmodule
