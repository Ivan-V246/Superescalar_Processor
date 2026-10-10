module store_buffer(
    input wire clk, rst,

    // Despacho — até 3 instruções por ciclo
    input wire [2:0]  v,                         // Quais slots são válidos
    input wire [2:0]  dst1, dst2, dst3,           // Destino de cada instrução
    input wire [4:0]  rob_id1, rob_id2, rob_id3, // Rob ids
    input wire [31:0] dado1, dado2, dado3,        // Dados a serem escritos

    // Consulta ao ROB
    output wire [4:0]  srid,   // Rob id do Store mais antigo aguardando commit
    input  wire [31:0] saddr,  // Endereço retornado pelo ROB

    // Commit do ROB
    input wire [2:0]  cv,
    input wire [4:0]  crob_id1, crob_id2, crob_id3,

    // Memória
    output wire        mem_req,
    output wire [31:0] mem_addr,
    output wire [31:0] mem_dado,

    // Sinal de parada
    output wire stop
);
    // Layout:
    // [36:32] → rob_id (5 bits)
    // [31:0]  → dado (32 bits)
    reg [36:0] buffer [0:15];
    reg [4:0] head, tail;

    wire [4:0] tail2 = tail + 1;
    wire [4:0] tail3 = tail + 2;

    // Filtragem interna — quais slots são Store
    wire is_store1 = v[0] & (dst1 == 3'b100);
    wire is_store2 = v[1] & (dst2 == 3'b100);
    wire is_store3 = v[2] & (dst3 == 3'b100);

    wire [2:0] dispatched = is_store1 + is_store2 + is_store3;

    // Commit
    wire commit = (cv[0] & (crob_id1 == buffer[head[3:0]][36:32])) |
                  (cv[1] & (crob_id2 == buffer[head[3:0]][36:32])) |
                  (cv[2] & (crob_id3 == buffer[head[3:0]][36:32]));

    assign srid     = buffer[head[3:0]][36:32];
    assign mem_req  = commit;
    assign mem_addr = saddr;
    assign mem_dado = buffer[head[3:0]][31:0];

    assign stop = ((tail - head) > 5'd13);

    integer i;
    always @(posedge clk) begin
        if (rst) begin
            head <= 5'd0;
            tail <= 5'd0;
            for (i = 0; i < 16; i = i + 1)
                buffer[i] <= 37'b0;
        end else begin
            tail <= tail + dispatched;

            // Despacho compactado
            case({is_store1, is_store2, is_store3})
                3'b001: buffer[tail[3:0]]  <= {rob_id3, dado3};
                3'b010: buffer[tail[3:0]]  <= {rob_id2, dado2};
                3'b011: begin
                    buffer[tail[3:0]]  <= {rob_id2, dado2};
                    buffer[tail2[3:0]] <= {rob_id3, dado3};
                end
                3'b100: buffer[tail[3:0]]  <= {rob_id1, dado1};
                3'b101: begin
                    buffer[tail[3:0]]  <= {rob_id1, dado1};
                    buffer[tail2[3:0]] <= {rob_id3, dado3};
                end
                3'b110: begin
                    buffer[tail[3:0]]  <= {rob_id1, dado1};
                    buffer[tail2[3:0]] <= {rob_id2, dado2};
                end
                3'b111: begin
                    buffer[tail[3:0]]  <= {rob_id1, dado1};
                    buffer[tail2[3:0]] <= {rob_id2, dado2};
                    buffer[tail3[3:0]] <= {rob_id3, dado3};
                end
            endcase

            if(commit) head <= head + 1;
        end
    end
endmodule
