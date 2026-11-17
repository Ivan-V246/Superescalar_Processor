`timescale 1ns/1ps
// Mede ciclos até concluir N instruções (+N=...) e imprime os contadores do despacho.
module tb_desempenho;
  reg clk=0, rst=1; always #5 clk=~clk;
  processador dut(.clk(clk),.rst(rst));
  integer i, alvo, feitas, ciclos;
  initial begin
    if (!$value$plusargs("N=%d", alvo)) alvo = 0;
    for (i=0;i<256;i=i+1) dut.mei.memoria[i]=32'h0;
    $readmemh("prog_aleatorio", dut.mei.memoria);
    for (i=0;i<2048;i=i+1) dut.med.memoria[i]=0;
    feitas=0; ciclos=0;
    repeat(2) @(posedge clk); #1 rst=0;
    while (feitas < alvo && ciclos < 20000) begin
      @(negedge clk);
      feitas = feitas + dut.rob_u.commited;
      @(posedge clk); #1;
      ciclos = ciclos + 1;
    end
    $display("PERF ciclos=%0d instrucoes=%0d", ciclos, feitas);
    `ifdef CNT
    $display("CNT %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
      dut.desp.cnt_ciclos, dut.desp.cnt_enviadas, dut.desp.cnt_fora_de_ordem,
      dut.desp.cnt_envio_1, dut.desp.cnt_envio_2, dut.desp.cnt_envio_3,
      dut.desp.cnt_parado_vazia, dut.desp.cnt_parado_operandos, dut.desp.cnt_parado_estrutura,
      dut.desp.cnt_parado_descarte, dut.desp.cnt_parado_fim, dut.desp.cnt_entrada_bloqueada);
    `endif
    $finish;
  end
endmodule
