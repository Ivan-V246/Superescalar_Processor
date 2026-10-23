`timescale 1ns/1ps

module tb_despacho;
    reg clk = 0;
    reg rst = 1;

    reg [2:0] mei_valid = 0;
    reg [31:0] mei_instr0 = 0, mei_instr1 = 0, mei_instr2 = 0;
    reg [31:0] mei_ordem0 = 0, mei_ordem1 = 0, mei_ordem2 = 0;
    wire mei_stop, pc_advence, ocupacao;

    reg load_buffer_stop = 0, store_buffer_stop = 0;
    wire [4:0] rob_id1, rob_id2, rob_id3;
    wire [31:0] dado1, dado2, dado3;
    reg stop = 0;
    reg [4:0] Rob_tail = 0;
    wire [2:0] v;
    wire [2:0] dst1, dst2, dst3;
    wire [4:0] rd1, rd2, rd3;

    reg path1_ready = 1, path2_ready = 1;
    wire path1_valid, path2_valid;
    wire [31:0] path1_instr, path2_instr;
    wire [31:0] path1_ordem, path2_ordem;
    wire [4:0] path1_rs1_addr, path1_rs2_addr;
    wire [4:0] path2_rs1_addr, path2_rs2_addr;
    reg [31:0] path1_rs1_data = 32'd10, path1_rs2_data = 32'd20;
    reg [31:0] path2_rs1_data = 32'd30, path2_rs2_data = 32'd40;

    despacho dut (
        .clk(clk), .rst(rst),
        .mei_valid(mei_valid),
        .mei_instr0(mei_instr0), .mei_instr1(mei_instr1), .mei_instr2(mei_instr2),
        .mei_ordem0(mei_ordem0), .mei_ordem1(mei_ordem1), .mei_ordem2(mei_ordem2),
        .mei_stop(mei_stop), .pc_advence(pc_advence), .ocupacao(ocupacao),
        .load_buffer_stop(load_buffer_stop), .store_buffer_stop(store_buffer_stop),
        .rob_id1(rob_id1), .rob_id2(rob_id2), .rob_id3(rob_id3),
        .dado1(dado1), .dado2(dado2), .dado3(dado3),
        .stop(stop), .Rob_tail(Rob_tail),
        .v(v), .dst1(dst1), .dst2(dst2), .dst3(dst3),
        .rd1(rd1), .rd2(rd2), .rd3(rd3),
        .path1_ready(path1_ready), .path2_ready(path2_ready),
        .path1_valid(path1_valid), .path2_valid(path2_valid),
        .path1_instr(path1_instr), .path2_instr(path2_instr),
        .path1_ordem(path1_ordem), .path2_ordem(path2_ordem),
        .path1_rs1_addr(path1_rs1_addr), .path1_rs2_addr(path1_rs2_addr),
        .path2_rs1_addr(path2_rs1_addr), .path2_rs2_addr(path2_rs2_addr),
        .path1_rs1_data(path1_rs1_data), .path1_rs2_data(path1_rs2_data),
        .path2_rs1_data(path2_rs1_data), .path2_rs2_data(path2_rs2_data)
    );

    always #5 clk = ~clk;

    function [31:0] add_instr;
        input [4:0] rd, rs1, rs2;
        begin
            add_instr = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
        end
    endfunction

    function [31:0] lw_instr;
        input [4:0] rd, rs1;
        begin
            lw_instr = {12'd0, rs1, 3'b010, rd, 7'b0000011};
        end
    endfunction

    task fail;
        input [255:0] message;
        begin
            $display("FALHOU: %0s (tempo %0t)", message, $time);
            $finish;
        end
    endtask

    task clear_inputs;
        begin
            mei_valid = 0;
            mei_instr0 = 0; mei_instr1 = 0; mei_instr2 = 0;
            mei_ordem0 = 0; mei_ordem1 = 0; mei_ordem2 = 0;
        end
    endtask

    initial begin
        $dumpfile("tb_despacho.vcd");
        $dumpvars(0, tb_despacho);
        $display("INICIO DOS TESTES");

        repeat (2) @(negedge clk);
        rst = 0;

        // Teste 1: ADD
        @(negedge clk);
        mei_valid = 3'b001;
        mei_instr0 = add_instr(5'd3, 5'd1, 5'd2);
        mei_ordem0 = 32'd100;
        @(posedge clk);
        #1;
        clear_inputs;
        #1;
        if (!path1_valid) fail("ADD nao foi despachada no caminho 1");
        if (path1_instr !== add_instr(5'd3, 5'd1, 5'd2)) fail("instrucao ADD incorreta");
        if (path1_ordem !== 32'd100) fail("ordem da ADD incorreta");
        if (rd1 !== 5'd3) fail("registrador destino da ADD incorreto");
        $display("PASSOU: despacho de uma ADD");

        @(posedge clk);
        #1;

        // Teste 2: duas ADD em ordem FIFO
        @(negedge clk);
        mei_valid = 3'b011;
        mei_instr0 = add_instr(5'd4, 5'd1, 5'd2);
        mei_instr1 = add_instr(5'd5, 5'd3, 5'd4);
        mei_ordem0 = 32'd200;
        mei_ordem1 = 32'd201;
        @(posedge clk);
        #1;
        clear_inputs;
        #1;
        if (!path1_valid || !path2_valid) fail("duas instrucoes nao foram despachadas");
        if (path1_ordem !== 32'd200 || path2_ordem !== 32'd201) fail("ordem FIFO incorreta");
        if (rd1 !== 5'd4 || rd2 !== 5'd5) fail("destinos das ADD incorretos");
        $display("PASSOU: despacho duplo e ordem FIFO");

        @(posedge clk);
        #1;

        // Teste 3: LOAD bloqueada e depois liberada
        @(negedge clk);
        mei_valid = 3'b001;
        mei_instr0 = lw_instr(5'd6, 5'd1);
        mei_ordem0 = 32'd300;
        @(posedge clk);
        #1;
        clear_inputs;
        load_buffer_stop = 1;
        #1;
        if (path1_valid) fail("LOAD foi despachada com load_buffer_stop ativo");
        if (ocupacao !== 1) fail("LOAD bloqueada nao permaneceu na FIFO");
        $display("PASSOU: bloqueio de LOAD pelo load buffer");

        load_buffer_stop = 0;
        #1;
        if (!path1_valid || path1_ordem !== 32'd300)
            fail("LOAD nao foi despachada apos liberar o buffer");
        $display("PASSOU: LOAD despachada apos liberar o buffer");

        @(posedge clk);
        #1;
        $display("TODOS OS TESTES PASSARAM");
        $finish;
    end

    // Timeout de seguranca para evitar simulacao infinita
    initial begin
        #1000;
        $display("FALHOU: timeout do testbench");
        $finish;
    end
endmodule