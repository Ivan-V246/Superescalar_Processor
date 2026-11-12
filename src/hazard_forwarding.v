//Hazard e forwarding
//
//O despacho lê os operandos no banco na hora em que envia a instrução. Só que o
//banco só é atualizado no commit, então ele pode estar com um valor velho.
//Exemplo:   addi x1, x0, 5
//           add  x2, x1, x1    <- se ler x1 no banco antes do commit do addi, lê 0
//
//Este módulo resolve isso de dois jeitos:
//  forwarding: se o resultado já foi calculado, entrega ele direto, sem esperar o banco
//  hazard:     se o resultado ainda nem foi calculado, segura a instrução na fila

module hazard_forwarding (
    input wire clk, rst,

    //Instruções na frente da fila do despacho (as próximas a sair)
    input wire [4:0] rs1_0, rs2_0,     //registradores que a 1ª lê
    input wire [4:0] rs1_1, rs2_1,     //registradores que a 2ª lê
    input wire [4:0] rd0, rd1,         //registrador que cada uma escreve
    input wire       escreve0, escreve1, //1 se escreve em registrador (ALU ou load)
    input wire       alu0, alu1,       //1 se é de ALU
    output wire      hazard0, hazard1, //1 = segura a 1ª / a 2ª na fila

    //Instruções enviadas aos caminhos neste ciclo
    //(a 1ª enviada é sempre a da frente da fila, e a 2ª, a seguinte)
    input wire       env1, env2,       //caminho 1 / 2 recebeu instrução
    input wire [4:0] env_rob1, env_rob2, //rob_id de cada uma

    //Resultados ficando prontos neste ciclo
    input wire        wb1, wb2,        //caminho 1 e 2 terminaram uma conta
    input wire [4:0]  rid1, rid2,      //rob_id da instrução que terminou
    input wire [31:0] r1, r2,          //resultado da conta
    input wire        lb_done,         //load buffer recebeu o dado de um load
    input wire [4:0]  lb_rid,
    input wire [31:0] lb_dado,

    //Commit (instruções gravando no banco neste ciclo)
    input wire [2:0]  we,
    input wire [4:0]  crd1, crd2, crd3,
    input wire [4:0]  crob_id1, crob_id2, crob_id3,

    //Valores lidos no banco (podem estar velhos) e valores certos que vão para os caminhos
    input wire [4:0]  p1_rs1, p1_rs2, p2_rs1, p2_rs2,
    input wire [31:0] banco_p1_rs1, banco_p1_rs2, banco_p2_rs1, banco_p2_rs2,
    output wire [31:0] p1_rs1_val, p1_rs2_val, p2_rs1_val, p2_rs2_val
);
    //------------------------------------------------------------------
    //Tabelas
    //
    //Tabela 1, "quem vai escrever cada registrador" (indexada pelo registrador):
    //  rat_ok[5] = 1      -> tem uma instrução em andamento que vai escrever em x5
    //  rat_id[5*5 +: 5]   -> posição dessa instrução no ROB (rob_id)
    //
    //Tabela 2, "resultados já calculados" (indexada pelo rob_id):
    //  res_ok[4] = 1      -> a instrução da posição 4 do ROB já tem resultado
    //  res[4*32 +: 32]    -> o resultado dela
    //
    //Ficam em vetores compridos, e não em memória (reg x [0:31]), porque com
    //memória o iverilog não percebia as mudanças e a instrução travava na fila.
    //A sintaxe v[i*5 +: 5] pega 5 bits a partir do bit i*5, ou seja, a "casa" i.
    //------------------------------------------------------------------
    reg [31:0]   rat_ok;
    reg [159:0]  rat_id;   //32 registradores x 5 bits
    reg [31:0]   res_ok;
    reg [1023:0] res;      //32 posições do ROB x 32 bits
    reg [31:0]   eh_alu;   //1 se a posição do ROB é de ALU. Para load e store, o caminho
                           //devolve um endereço, e não o resultado final, então não serve

    //------------------------------------------------------------------
    //Consultas
    //
    //Cada consulta_reg responde, para um registrador:
    //  disponivel -> o valor já existe? (no banco, na tabela ou chegando agora)
    //  valor      -> qual é o valor certo
    //
    //c0..c3: registradores das duas instruções da frente. Só usamos o "disponivel",
    //        para decidir se elas podem sair.
    //v0..v3: registradores das instruções que estão saindo para os caminhos.
    //        Usamos o "valor": é aqui que o forwarding acontece.
    //------------------------------------------------------------------
    wire        d_rs1_0, d_rs2_0, d_rs1_1, d_rs2_1;
    wire [31:0] nc0, nc1, nc2, nc3;    //valores das consultas c0..c3, não usados
    wire        nd0, nd1, nd2, nd3;    //"disponivel" das consultas v0..v3, não usado

    consulta_reg c0 (.r(rs1_0), .do_banco(32'd0), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(d_rs1_0), .valor(nc0));
    consulta_reg c1 (.r(rs2_0), .do_banco(32'd0), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(d_rs2_0), .valor(nc1));
    consulta_reg c2 (.r(rs1_1), .do_banco(32'd0), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(d_rs1_1), .valor(nc2));
    consulta_reg c3 (.r(rs2_1), .do_banco(32'd0), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(d_rs2_1), .valor(nc3));

    consulta_reg v0 (.r(p1_rs1), .do_banco(banco_p1_rs1), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(nd0), .valor(p1_rs1_val));
    consulta_reg v1 (.r(p1_rs2), .do_banco(banco_p1_rs2), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(nd1), .valor(p1_rs2_val));
    consulta_reg v2 (.r(p2_rs1), .do_banco(banco_p2_rs1), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(nd2), .valor(p2_rs1_val));
    consulta_reg v3 (.r(p2_rs2), .do_banco(banco_p2_rs2), .rat_ok(rat_ok), .rat_id(rat_id), .res_ok(res_ok), .res(res), .eh_alu(eh_alu),
                     .wb1(wb1), .rid1(rid1), .r1(r1), .wb2(wb2), .rid2(rid2), .r2(r2), .lb_done(lb_done), .lb_rid(lb_rid), .lb_dado(lb_dado),
                     .disponivel(nd3), .valor(p2_rs2_val));

    //------------------------------------------------------------------
    //Hazard: segura a instrução se algum valor que ela lê ainda não existe
    //------------------------------------------------------------------
    assign hazard0 = !d_rs1_0 || !d_rs2_0;

    //A 2ª também espera se lê o registrador que a 1ª escreve no mesmo ciclo,
    //porque as duas sairiam juntas e a 1ª ainda nem começou a calcular.
    //Ex.: addi x1, x0, 5 e add x2, x1, x1 na frente da fila ao mesmo tempo
    assign hazard1 = !d_rs1_1 || !d_rs2_1 ||
                     (escreve0 && rd0 != 5'd0 && (rs1_1 == rd0 || rs2_1 == rd0));

    //------------------------------------------------------------------
    //Atualização das tabelas, a cada clock
    //------------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            rat_ok <= 0; rat_id <= 0; res_ok <= 0; res <= 0; eh_alu <= 0;
        end else begin
            //1) Resultado pronto: guarda na tabela 2, para o forwarding usar nos próximos ciclos
            if (wb1 && eh_alu[rid1]) begin res_ok[rid1] <= 1'b1; res[rid1*32 +: 32] <= r1; end
            if (wb2 && eh_alu[rid2]) begin res_ok[rid2] <= 1'b1; res[rid2*32 +: 32] <= r2; end
            if (lb_done)             begin res_ok[lb_rid] <= 1'b1; res[lb_rid*32 +: 32] <= lb_dado; end

            //2) Commit: o valor foi para o banco, então o registrador deixa de estar pendente.
            //   Só apaga se quem está fazendo commit ainda é o dono do registrador. Se uma
            //   instrução mais nova já vai escrever nele, a anotação continua valendo.
            if (we[0] && crd1 != 0 && rat_ok[crd1] && rat_id[crd1*5 +: 5] == crob_id1) rat_ok[crd1] <= 1'b0;
            if (we[1] && crd2 != 0 && rat_ok[crd2] && rat_id[crd2*5 +: 5] == crob_id2) rat_ok[crd2] <= 1'b0;
            if (we[2] && crd3 != 0 && rat_ok[crd3] && rat_id[crd3*5 +: 5] == crob_id3) rat_ok[crd3] <= 1'b0;

            //3) Envio: a posição do ROB começa "sem resultado" e a instrução vira a dona
            //   do registrador que ela escreve.
            //   A tabela é atualizada no envio, e não na entrada da fila: como a fila sai em
            //   ordem, quem está esperando na fila nunca vê um produtor que vem depois dele.
            //   Fica por último de propósito: quando duas atribuições caem no mesmo bit na
            //   mesma borda, vale a última. Assim o envio ganha do commit, e a 2ª enviada
            //   ganha da 1ª (a mais nova é sempre a dona).
            if (env1) begin res_ok[env_rob1] <= 1'b0; eh_alu[env_rob1] <= alu0; end
            if (env2) begin res_ok[env_rob2] <= 1'b0; eh_alu[env_rob2] <= alu1; end
            if (env1 && escreve0 && rd0 != 0) begin rat_ok[rd0] <= 1'b1; rat_id[rd0*5 +: 5] <= env_rob1; end
            if (env2 && escreve1 && rd1 != 0) begin rat_ok[rd1] <= 1'b1; rat_id[rd1*5 +: 5] <= env_rob2; end
        end
    end
endmodule


//Consulta de um registrador r: o valor já existe? Qual é o valor certo?
module consulta_reg (
    input wire [4:0]    r,
    input wire [31:0]   do_banco,
    input wire [31:0]   rat_ok,
    input wire [159:0]  rat_id,
    input wire [31:0]   res_ok,
    input wire [1023:0] res,
    input wire [31:0]   eh_alu,
    input wire          wb1, wb2, lb_done,
    input wire [4:0]    rid1, rid2, lb_rid,
    input wire [31:0]   r1, r2, lb_dado,
    output wire         disponivel,
    output wire [31:0]  valor
);
    wire       pendente = (r != 5'd0) && rat_ok[r];   //alguém vai escrever em r? (x0 nunca muda)
    wire [4:0] p        = rat_id[r*5 +: 5];           //quem: a posição no ROB

    //O resultado de p está chegando neste ciclo?
    wire vem_c1   = wb1 && rid1 == p && eh_alu[p];    //pelo caminho 1
    wire vem_c2   = wb2 && rid2 == p && eh_alu[p];    //pelo caminho 2
    wire vem_load = lb_done && lb_rid == p;           //pelo load buffer

    //Disponível se ninguém vai escrever, se já está na tabela ou se está chegando agora
    assign disponivel = !pendente || res_ok[p] || vem_c1 || vem_c2 || vem_load;

    //Escolhe de onde vem o valor
    assign valor = !pendente ? do_banco :        //ninguém vai escrever: o banco está certo
                   vem_c1    ? r1 :              //forwarding do caminho 1
                   vem_c2    ? r2 :              //forwarding do caminho 2
                   vem_load  ? lb_dado :         //forwarding do load
                               res[p*32 +: 32];  //já tinha ficado pronto antes
endmodule
