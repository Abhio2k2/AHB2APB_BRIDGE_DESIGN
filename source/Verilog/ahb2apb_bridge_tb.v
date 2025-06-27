

`timescale 1ns / 1ps

module tb_ahb2apb_bridge;

    // Testbench Signals
    reg hclk, hrstn, hsel, hwrite;
    reg [1:0] htrans;
    reg [31:0] haddr, hwdata, prdata;

    wire psel, penable, pwrite, hresp, hready;
    wire [31:0] hrdata, paddr, pwdata;

    // Instantiate the DUT (Device Under Test)
    ahb2apb_bridge uut (
        .hclk(hclk),
        .hrstn(hrstn),
        .hsel(hsel),
        .hwrite(hwrite),
        .htrans(htrans),
        .haddr(haddr),
        .hwdata(hwdata),
        .prdata(prdata),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .hresp(hresp),
        .hready(hready),
        .hrdata(hrdata),
        .paddr(paddr),
        .pwdata(pwdata)
    );

    // Clock Generation
    initial hclk = 0;
    always #5 hclk = ~hclk;  // 100MHz Clock

    // Stimulus Process
    initial begin
        // Initialize Inputs
        hrstn = 0;
        hsel = 0;
        hwrite = 0;
        htrans = 2'b00;
        haddr = 32'd0;
        hwdata = 32'd0;
        prdata = 32'd100;  // APB slave will return this dummy read data

        // Apply Reset
        #10 hrstn = 1;

        // Wait for a few cycles
        #10;
     
        // Write Transaction (Non-Pipelined)
       
        @(posedge hclk);
        hsel = 1;
        hwrite = 1;
        htrans = 2'b10;   // NONSEQ
        haddr = 32'hA000_0000;
        hwdata = 32'h1111_1111;

        @(posedge hclk);
        hsel = 0;         // Deassert after sending address and data
        htrans = 2'b00;

        // Wait for bridge to process
        repeat (3) @(posedge hclk);
     
        // Read Transaction
       
        @(posedge hclk);
        hsel = 1;
        hwrite = 0;
        htrans = 2'b10;   // NONSEQ
        haddr = 32'hA000_0004;

        @(posedge hclk);
        hsel = 0;
        htrans = 2'b00;

        // Wait for bridge to process
        repeat (3) @(posedge hclk);

        // Pipelined Write Transactions
        
        @(posedge hclk);
        hsel = 1;
        hwrite = 1;
        htrans = 2'b10;
        haddr = 32'hA000_0008;
        hwdata = 32'h2222_2222;

        @(posedge hclk);
        hsel = 1;                 // Keep hsel high to simulate pipeline
        hwrite = 1;
        htrans = 2'b11;           // SEQ
        haddr = 32'hA000_000C;
        hwdata = 32'h3333_3333;

        @(posedge hclk);
        hsel = 0;
        htrans = 2'b00;

        // Wait for bridge to process
        repeat (4) @(posedge hclk);

        // Finish Simulation
  
        $display("Test Completed");
        $stop;
    end

endmodule
