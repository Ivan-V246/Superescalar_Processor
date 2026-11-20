//Hazard e forwarding com renomeação na alocação
//
//O despacho envia fora de ordem, então "quem produz cada operando" é decidido na
//ENTRADA da fila, que continua em ordem de programa. Para cada instrução (indexada
//pelo rob_id), esta unidade guarda de onde vem cada operando:
//  - do banco (nenhuma instrução em andamento escreve o registrador), ou
//  - do resultado de uma instrução em andamento (o rob_id dela, a "etiqueta").
//
//A cada ciclo ela devolve ao despacho um vetor "pronto", também indexado pelo rob_id:
//a instrução pode sair se os dois operandos já existem (no banco, na tabela de
//resultados ou chegando neste ciclo). Para as instruções que saem, ela entrega os
//valores certos aos caminhos (forwarding).
//
//Exemplo:  1: addi x1, x0, 5      x1 passa a ser produzido pelo rob_id 1
//          2: lw   x2, 0(x3)
//          3: add  x4, x1, x2     rs1 <- etiqueta 1, rs2 <- etiqueta 2
//          4: addi x5, x0, 7      não depende de ninguém: pode sair antes da 3
//
//Tabelas (vetores achatados, como na versão anterior, porque o iverilog não acompanha
//bem memórias em lógica combinacional; v[i*5 +: 5] é a "casa" i):
//  RAT (Register Alias Table), por registrador:
//    rat_ok[r]          -> há instrução em andamento que vai escrever r
//    rat_id[r*5 +: 5]   -> o rob_id dela
//  Por rob_id:
//    res_ok[x], res[x*32 +: 32] -> resultado já calculado e o valor
//    eh_alu[x]          -> o resultado vem do caminho (ULA, JAL, JALR); para load e
//                          store o caminho devolve o endereço, que não serve como valor
//    s1_banco[x], s1_tag[x*5 +: 5] -> origem do rs1 (banco ou etiqueta)
//    s2_banco[x], s2_tag[x*5 +: 5] -> origem do rs2
//  Cópias da RAT para o descarte, NCK = 4 (uma por desvio ainda não resolvido):
//    ck_ok[c*32 +: 32], ck_id[c*160 +: 160] -> a cópia c
//    ck_usado[c], ck_dono[c*5 +: 5]         -> ocupada e o rob_id do desvio dono dela
//  Como os desvios saem em ordem e o caminho 3 os resolve em 1 ciclo, raramente há mais de
//  2 pendentes. Se as 4 cópias estiverem ocupadas, o despacho segura a entrada de um grupo
//  com desvio (ck_livres) até uma ser liberada.
//
//Commit: quando uma instrução grava no banco, quem dependia da etiqueta dela passa a
//ler o banco. Isso evita que o rob_id, ao ser reaproveitado, confunda os consumidores.
//
//Descarte (flush_ok): a RAT volta à cópia tirada na alocação do desvio que errou, e todas
//as cópias são liberadas (os desvios mais antigos já foram resolvidos, porque saem em ordem,
//e os mais novos foram descartados). Os commits feitos desde a cópia também são aplicados a ela.
//Um desvio resolvido sem erro (wb3) libera a sua cópia.
module hazard_forwarding (
    input wire clk, rst,

    //Alocação (entrada na fila do despacho), em ordem de programa: a posição 0 é a mais antiga
    input wire [2:0] al_v,
    input wire [4:0] al_rob0, al_rob1, al_rob2,
    input wire [4:0] al_rs1_0, al_rs1_1, al_rs1_2,   //0 quando não usa
    input wire [4:0] al_rs2_0, al_rs2_1, al_rs2_2,
    input wire [4:0] al_rd0, al_rd1, al_rd2,
    input wire       al_escreve0, al_escreve1, al_escreve2, //escreve registrador (ULA, load, JAL/JALR)
    input wire       al_alu0, al_alu1, al_alu2,             //resultado vem do caminho
    input wire       al_desvio0, al_desvio1, al_desvio2,    //tira cópia da RAT

    //Prontidão de cada instrução, pelo rob_id
    output wire [31:0] pronto,

    //Cópias livres para desvios (o despacho só aceita um grupo se houver uma por desvio)
    output wire [2:0]  ck_livres,

    //Resultados ficando prontos neste ciclo
    input wire        wb1, wb2, wb3,
    input wire [4:0]  rid1, rid2, rid3,
    input wire [31:0] r1, r2, r3,
    input wire        lb_done,
    input wire [4:0]  lb_rid,
    input wire [31:0] lb_dado,

    //Commit (instruções gravando no banco)
    input wire [2:0]  we,
    input wire [4:0]  crd1, crd2, crd3,
    input wire [4:0]  crob_id1, crob_id2, crob_id3,

    //Descarte
    input wire        flush_ok,
    input wire [4:0]  flush_rob_id,

    //Operandos das instruções enviadas: rob_id de cada caminho, valor lido no banco e valor certo
    input  wire [4:0]  p1_rob, p2_rob, p3_rob,
    input  wire [31:0] banco_p1_rs1, banco_p1_rs2,
    input  wire [31:0] banco_p2_rs1, banco_p2_rs2,
    input  wire [31:0] banco_p3_rs1, banco_p3_rs2,
    output reg  [31:0] p1_rs1_val, p1_rs2_val,
    output reg  [31:0] p2_rs1_val, p2_rs2_val,
    output reg  [31:0] p3_rs1_val, p3_rs2_val
);
    //------------------------------------------------------------------
    //Tabelas
    //------------------------------------------------------------------
    reg [31:0]   rat_ok;
    reg [159:0]  rat_id;
    reg [31:0]   res_ok;
    reg [1023:0] res;
    reg [31:0]   eh_alu;
    reg [31:0]   s1_banco, s2_banco;
    reg [159:0]  s1_tag, s2_tag;
    localparam NCK = 4;
    reg [NCK*32-1:0]  ck_ok;
    reg [NCK*160-1:0] ck_id;
    reg [NCK-1:0]     ck_usado;
    reg [NCK*5-1:0]   ck_dono;

    assign ck_livres = !ck_usado[0] + !ck_usado[1] + !ck_usado[2] + !ck_usado[3];

    //------------------------------------------------------------------
    //Resultados chegando neste ciclo (para pronto e forwarding)
    //Só vale o resultado de caminho quando ele é o valor final (eh_alu)
    //------------------------------------------------------------------
    wire c1 = wb1 && eh_alu[rid1];
    wire c2 = wb2 && eh_alu[rid2];
    wire c3 = wb3 && eh_alu[rid3];

    wire [31:0] agora = (c1 ? (32'd1 << rid1) : 32'd0) |
                        (c2 ? (32'd1 << rid2) : 32'd0) |
                        (c3 ? (32'd1 << rid3) : 32'd0) |
                        (lb_done ? (32'd1 << lb_rid) : 32'd0);

    //------------------------------------------------------------------
    //Prontidão: cada operando vem do banco, de um resultado guardado ou de um chegando agora
    //------------------------------------------------------------------
    genvar g;
    generate
        for (g = 0; g < 32; g = g + 1) begin : gp
            wire [4:0] t1 = s1_tag[g*5 +: 5];
            wire [4:0] t2 = s2_tag[g*5 +: 5];
            wire ok1 = s1_banco[g] || res_ok[t1] || agora[t1];
            wire ok2 = s2_banco[g] || res_ok[t2] || agora[t2];
            assign pronto[g] = ok1 && ok2;
        end
    endgenerate

    //------------------------------------------------------------------
    //Valores para os caminhos
    //------------------------------------------------------------------
    function [31:0] valor;
        input        do_banco;
        input [4:0]  t;
        input [31:0] v_banco;
        input [31:0] v_res_ok;
        input [1023:0] v_res;
        input        a1, a2, a3, al;
        input [4:0]  i1, i2, i3, il;
        input [31:0] x1, x2, x3, xl;
        begin
            if (do_banco)               valor = v_banco;
            else if (v_res_ok[t])       valor = v_res[t*32 +: 32];
            else if (a1 && i1 == t)     valor = x1;
            else if (a2 && i2 == t)     valor = x2;
            else if (a3 && i3 == t)     valor = x3;
            else if (al && il == t)     valor = xl;
            else                        valor = v_banco;   //não deveria acontecer (não pronta)
        end
    endfunction

    always @* begin
        p1_rs1_val = valor(s1_banco[p1_rob], s1_tag[p1_rob*5 +: 5], banco_p1_rs1, res_ok, res,
                           c1, c2, c3, lb_done, rid1, rid2, rid3, lb_rid, r1, r2, r3, lb_dado);
        p1_rs2_val = valor(s2_banco[p1_rob], s2_tag[p1_rob*5 +: 5], banco_p1_rs2, res_ok, res,
                           c1, c2, c3, lb_done, rid1, rid2, rid3, lb_rid, r1, r2, r3, lb_dado);
        p2_rs1_val = valor(s1_banco[p2_rob], s1_tag[p2_rob*5 +: 5], banco_p2_rs1, res_ok, res,
                           c1, c2, c3, lb_done, rid1, rid2, rid3, lb_rid, r1, r2, r3, lb_dado);
        p2_rs2_val = valor(s2_banco[p2_rob], s2_tag[p2_rob*5 +: 5], banco_p2_rs2, res_ok, res,
                           c1, c2, c3, lb_done, rid1, rid2, rid3, lb_rid, r1, r2, r3, lb_dado);
        p3_rs1_val = valor(s1_banco[p3_rob], s1_tag[p3_rob*5 +: 5], banco_p3_rs1, res_ok, res,
                           c1, c2, c3, lb_done, rid1, rid2, rid3, lb_rid, r1, r2, r3, lb_dado);
        p3_rs2_val = valor(s2_banco[p3_rob], s2_tag[p3_rob*5 +: 5], banco_p3_rs2, res_ok, res,
                           c1, c2, c3, lb_done, rid1, rid2, rid3, lb_rid, r1, r2, r3, lb_dado);
    end

    //------------------------------------------------------------------
    //Atualização das tabelas
    //Os valores "_n" são calculados em sequência, na ordem em que os eventos
    //precisam ser aplicados, e gravados no fim.
    //------------------------------------------------------------------
    reg [31:0]   rat_ok_n, res_ok_n, eh_alu_n, s1_banco_n, s2_banco_n;
    reg [159:0]  rat_id_n, s1_tag_n, s2_tag_n;
    reg [NCK*32-1:0]  ck_ok_n;
    reg [NCK*160-1:0] ck_id_n;
    reg [NCK-1:0]     ck_usado_n;
    reg [NCK*5-1:0]   ck_dono_n;
    reg               achou;
    reg [4:0]    a_rob, a_rs1, a_rs2, a_rd, c_rd, c_rob;
    reg          a_esc, a_alu, a_desv, c_we;
    integer k, b, x, cc;

    always @(posedge clk) begin
        if (rst) begin
            rat_ok <= 0; rat_id <= 0; res_ok <= 0; res <= 0; eh_alu <= 0;
            s1_banco <= 32'hFFFFFFFF; s2_banco <= 32'hFFFFFFFF; s1_tag <= 0; s2_tag <= 0;
            ck_ok <= 0; ck_id <= 0; ck_usado <= 0; ck_dono <= 0;
        end else begin
            rat_ok_n = rat_ok; rat_id_n = rat_id;
            res_ok_n = res_ok; eh_alu_n = eh_alu;
            s1_banco_n = s1_banco; s2_banco_n = s2_banco; s1_tag_n = s1_tag; s2_tag_n = s2_tag;
            ck_ok_n = ck_ok; ck_id_n = ck_id; ck_usado_n = ck_usado; ck_dono_n = ck_dono;

            //1) Descarte: a RAT volta ao estado da alocação do desvio que errou;
            //   todas as cópias ficam livres. Sem descarte, o desvio resolvido libera a sua.
            if (flush_ok) begin
                for (b = 0; b < NCK; b = b + 1)
                    if (ck_usado[b] && ck_dono[b*5 +: 5] == flush_rob_id) begin
                        rat_ok_n = ck_ok[b*32 +: 32];
                        rat_id_n = ck_id[b*160 +: 160];
                    end
                ck_usado_n = 0;
            end else if (wb3) begin
                for (b = 0; b < NCK; b = b + 1)
                    if (ck_usado[b] && ck_dono[b*5 +: 5] == rid3) ck_usado_n[b] = 1'b0;
            end

            //2) Commit: o valor foi para o banco
            for (cc = 0; cc < 3; cc = cc + 1) begin
                case (cc)
                    0: begin c_we = we[0]; c_rd = crd1; c_rob = crob_id1; end
                    1: begin c_we = we[1]; c_rd = crd2; c_rob = crob_id2; end
                    default: begin c_we = we[2]; c_rd = crd3; c_rob = crob_id3; end
                endcase
                if (c_we && c_rd != 5'd0) begin
                    //Deixa de ser pendente, se ainda é o dono do registrador
                    if (rat_ok_n[c_rd] && rat_id_n[c_rd*5 +: 5] == c_rob) rat_ok_n[c_rd] = 1'b0;
                    //O mesmo em todas as cópias
                    for (b = 0; b < NCK; b = b + 1)
                        if (ck_ok_n[b*32 + c_rd] && ck_id_n[b*160 + c_rd*5 +: 5] == c_rob)
                            ck_ok_n[b*32 + c_rd] = 1'b0;
                    //Quem esperava esta etiqueta passa a ler o banco
                    for (x = 0; x < 32; x = x + 1) begin
                        if (!s1_banco_n[x] && s1_tag_n[x*5 +: 5] == c_rob) s1_banco_n[x] = 1'b1;
                        if (!s2_banco_n[x] && s2_tag_n[x*5 +: 5] == c_rob) s2_banco_n[x] = 1'b1;
                    end
                end
            end

            //3) Resultados: guarda para o forwarding
            if (c1) begin res_ok_n[rid1] = 1'b1; res[rid1*32 +: 32] <= r1; end
            if (c2) begin res_ok_n[rid2] = 1'b1; res[rid2*32 +: 32] <= r2; end
            if (c3) begin res_ok_n[rid3] = 1'b1; res[rid3*32 +: 32] <= r3; end
            if (lb_done) begin res_ok_n[lb_rid] = 1'b1; res[lb_rid*32 +: 32] <= lb_dado; end

            //4) Alocação, em ordem (no ciclo do descarte o que chega é do caminho errado)
            if (!flush_ok) begin
                for (k = 0; k < 3; k = k + 1) begin
                    if (al_v[k]) begin
                        case (k)
                            0: begin a_rob = al_rob0; a_rs1 = al_rs1_0; a_rs2 = al_rs2_0; a_rd = al_rd0;
                                     a_esc = al_escreve0; a_alu = al_alu0; a_desv = al_desvio0; end
                            1: begin a_rob = al_rob1; a_rs1 = al_rs1_1; a_rs2 = al_rs2_1; a_rd = al_rd1;
                                     a_esc = al_escreve1; a_alu = al_alu1; a_desv = al_desvio1; end
                            default: begin a_rob = al_rob2; a_rs1 = al_rs1_2; a_rs2 = al_rs2_2; a_rd = al_rd2;
                                     a_esc = al_escreve2; a_alu = al_alu2; a_desv = al_desvio2; end
                        endcase

                        //Origem de cada operando: banco ou etiqueta do produtor mais recente
                        if (a_rs1 == 5'd0 || !rat_ok_n[a_rs1]) s1_banco_n[a_rob] = 1'b1;
                        else begin s1_banco_n[a_rob] = 1'b0; s1_tag_n[a_rob*5 +: 5] = rat_id_n[a_rs1*5 +: 5]; end
                        if (a_rs2 == 5'd0 || !rat_ok_n[a_rs2]) s2_banco_n[a_rob] = 1'b1;
                        else begin s2_banco_n[a_rob] = 1'b0; s2_tag_n[a_rob*5 +: 5] = rat_id_n[a_rs2*5 +: 5]; end

                        //A posição do ROB começa sem resultado
                        res_ok_n[a_rob] = 1'b0;
                        eh_alu_n[a_rob] = a_alu;

                        //A instrução vira a dona do registrador que escreve
                        if (a_esc && a_rd != 5'd0) begin
                            rat_ok_n[a_rd] = 1'b1;
                            rat_id_n[a_rd*5 +: 5] = a_rob;
                        end

                        //Desvio: cópia da RAT já com ele (JAL/JALR escrevem rd), na primeira
                        //cópia livre (o despacho garante que há uma)
                        if (a_desv) begin
                            achou = 1'b0;
                            for (b = 0; b < NCK; b = b + 1)
                                if (!achou && !ck_usado_n[b]) begin
                                    achou = 1'b1;
                                    ck_usado_n[b] = 1'b1;
                                    ck_dono_n[b*5 +: 5]   = a_rob;
                                    ck_ok_n[b*32 +: 32]   = rat_ok_n;
                                    ck_id_n[b*160 +: 160] = rat_id_n;
                                end
                        end
                    end
                end
            end

            rat_ok <= rat_ok_n; rat_id <= rat_id_n;
            res_ok <= res_ok_n; eh_alu <= eh_alu_n;
            s1_banco <= s1_banco_n; s2_banco <= s2_banco_n; s1_tag <= s1_tag_n; s2_tag <= s2_tag_n;
            ck_ok <= ck_ok_n; ck_id <= ck_id_n; ck_usado <= ck_usado_n; ck_dono <= ck_dono_n;
        end
    end
endmodule
