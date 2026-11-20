`timescale 1ns/1ps
module tb_banco_registradores;
    reg clk = 0;
    reg rst = 0;
    reg [29:0] read_addresses = 0;
    wire [191:0] read_values;
    reg [2:0] we = 0;
    reg [14:0] write_addresses = 0;
    reg [95:0] write_values = 0;
    reg [31:0] model [0:31];
    reg [31:0] valor_capturado;
    integer r, lane, mask, cycle, seed, checks = 0;

    banco_registradores dut (
        .clk(clk), .rst(rst),
        .rs1_1(read_addresses[4:0]), .rs2_1(read_addresses[9:5]),
        .rs1_2(read_addresses[14:10]), .rs2_2(read_addresses[19:15]),
        .rs1_3(read_addresses[24:20]), .rs2_3(read_addresses[29:25]),
        .valor_rs1_1(read_values[31:0]), .valor_rs2_1(read_values[63:32]),
        .valor_rs1_2(read_values[95:64]), .valor_rs2_2(read_values[127:96]),
        .valor_rs1_3(read_values[159:128]), .valor_rs2_3(read_values[191:160]),
        .we(we), .rd1(write_addresses[4:0]), .rd2(write_addresses[9:5]),
        .rd3(write_addresses[14:10]), .dado1(write_values[31:0]),
        .dado2(write_values[63:32]), .dado3(write_values[95:64])
    );
    always #5 clk = ~clk;
    // Representa um consumidor sincrono das leituras do banco.
    always @(posedge clk) valor_capturado <= read_values[31:0];

    // Modelo por registrador, com prioridade explicita da porta mais nova.
    always @(posedge clk) begin
        for (r = 0; r < 32; r = r + 1) begin
            if (rst || r == 0) model[r] = 0;
            else if (we[2] && write_addresses[14:10] == r)
                model[r] = write_values[95:64];
            else if (we[1] && write_addresses[9:5] == r)
                model[r] = write_values[63:32];
            else if (we[0] && write_addresses[4:0] == r)
                model[r] = write_values[31:0];
        end
    end
    task check_reads;
        integer port_number, address;
        begin
            for (port_number = 0; port_number < 6; port_number = port_number + 1) begin
                address = read_addresses[port_number*5 +: 5];
                if (read_values[port_number*32 +: 32] !== model[address])
                    $fatal(1, "Leitura %0d de x%0d: recebido=%h esperado=%h",
                           port_number, address, read_values[port_number*32 +: 32], model[address]);
                checks = checks + 1;
            end
        end
    endtask
    task check_all_registers;
        integer address;
        begin
            // Cada registrador e testado em todas as seis portas, sem clock.
            for (address = 0; address < 32; address = address + 1) begin
                read_addresses = {6{address[4:0]}};
                #0.01;
                check_reads;
            end
        end
    endtask
    task tick;
        begin @(posedge clk); #1; end
    endtask
    task drive;
        begin @(negedge clk); #1; end
    endtask

    initial begin #20000; $fatal(1, "Timeout do banco"); end
    initial begin
        seed = 32'h12345678;
        #1;
        if (read_values !== 192'd0) $fatal(1, "x0 nao e constante antes do reset");
        rst = 1; tick;
        check_all_registers;
        drive; rst = 0;

        $display("1: tres escritas e seis leituras simultaneas");
        we = 3'b111;
        write_addresses = {5'd31, 5'd2, 5'd1};
        write_values = {32'hffffffff, 32'h80000000, 32'h01234567};
        read_addresses = {5'd31, 5'd2, 5'd1, 5'd31, 5'd2, 5'd1};
        #1; check_reads; // Novos dados nao aparecem antes da borda.
        tick;
        if (valor_capturado !== 32'd0 || read_values[31:0] !== 32'h01234567)
            $fatal(1, "Captura na borda deve ver antigo; leitura apos borda deve ver novo");
        check_reads; check_all_registers;

        $display("2: todas as oito habilitacoes e colisoes no mesmo registrador");
        for (mask = 0; mask < 8; mask = mask + 1) begin
            drive;
            we = mask[2:0];
            write_addresses = {3{5'd9}};
            write_values = {32'h33333333, 32'h22222222, 32'h11111111};
            tick; check_all_registers;
        end

        $display("3: colisao parcial preserva escrita em outro registrador");
        drive; we = 3'b111;
        write_addresses = {5'd10, 5'd11, 5'd10};
        write_values = {32'h30303030, 32'h20202020, 32'h10101010};
        tick; check_all_registers;

        $display("4: escritas em x0 sao ignoradas em todas as portas");
        drive; we = 3'b111;
        write_addresses = 0; write_values = {96{1'b1}};
        tick; check_all_registers;

        $display("5: reset sincrono tem prioridade sobre tres escritas");
        drive;
        read_addresses = {6{5'd31}};
        write_addresses = {5'd31, 5'd2, 5'd1};
        rst = 1;
        #1;
        if (read_values[31:0] !== 32'hffffffff)
            $fatal(1, "Reset ocorreu antes da borda positiva");
        tick; check_all_registers;
        drive; rst = 0; we = 0;

        $display("6: 200 ciclos aleatorios com auditoria completa do banco");
        for (cycle = 0; cycle < 200; cycle = cycle + 1) begin
            drive;
            we = $random(seed);
            for (lane = 0; lane < 3; lane = lane + 1) begin
                write_addresses[lane*5 +: 5] = $random(seed);
                write_values[lane*32 +: 32] = $random(seed);
            end
            for (lane = 0; lane < 6; lane = lane + 1)
                read_addresses[lane*5 +: 5] = $random(seed);
            #1; check_reads;
            tick; check_reads; check_all_registers;
        end
        $display("PASS banco: %0d leituras verificadas", checks);
        $finish;
    end
endmodule
