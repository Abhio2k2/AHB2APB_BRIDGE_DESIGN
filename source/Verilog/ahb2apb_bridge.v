// AHB to APB Bridge

module ahb2apb_bridge (
    input hclk, hrstn, hsel, hwrite,                      // Clock, Reset, Slave Select, Write enable
    input [1:0] htrans,                                   // AHB transfer type (2'b10 → Non-seq, 2'b11 → Seq)
    input [31:0] haddr, hwdata, prdata,                   // AHB address, AHB write data, APB read data
    output reg psel, penable, pwrite, hresp, hready,      // APB control signals, AHB response and ready
    output reg [31:0] hrdata, paddr, pwdata               // AHB read data, APB address, APB write data
);

    // Internal Registers
    reg [31:0] haddr_temp, hwdata_temp;                   // Temporary storage for AHB address and write data
    reg [2:0] present_state, next_state;                  // FSM current and next state
    reg valid;                                            // Valid transfer flag

    // State Encoding
    parameter idle       = 3'b000;                        // Idle state
    parameter read       = 3'b001;                        // Read setup state
    parameter wwait      = 3'b010;                        // Write wait state
    parameter write      = 3'b011;                        // Write setup state
    parameter write_p    = 3'b100;                        // Pipelined write setup state
    parameter wenable    = 3'b101;                        // Write enable state
    parameter wenable_p  = 3'b110;                        // Pipelined write enable state
    parameter renable    = 3'b111;                        // Read enable state

    // State Register (Sequential Block)
    always @(posedge hclk or negedge hrstn) begin
        if (!hrstn)                                       // If reset is low (active)
            present_state <= idle;                        // Reset to idle state
        else
            present_state <= next_state;                  // Move to next state on clock edge
    end

    // Combinational Next State and Output Logic
    always @(*) begin
        // Default Signal Assignments (Important to avoid latches)
        psel = 1'b0;                                      // APB peripheral not selected by default
        penable = 1'b0;                                   // APB enable low by default
        pwrite = 1'b0;                                    // APB write low by default
        hready = 1'b1;                                    // AHB is ready by default
        hresp = 1'b0;                                     // AHB response OKAY by default
        paddr = 32'b0;                                    // APB address default to zero
        pwdata = 32'b0;                                   // APB write data default to zero
        hrdata = 32'b0;                                   // AHB read data default to zero

        // Transfer Validity Check
        if (hsel == 1'b1 && (htrans == 2'b10 || htrans == 2'b11))
            valid = 1'b1;                                 // Valid transfer: selected and active transfer
        else
            valid = 1'b0;                                 // Invalid transfer: not selected or idle

        // FSM State Machine
        case (present_state)

            idle: begin                                   // Idle state: waiting for valid AHB transaction
                if (valid == 1'b0)
                    next_state = idle;                    // Stay in idle if no valid transfer
                else if (valid == 1'b1 && hwrite == 1'b0)
                    next_state = read;                    // Move to read state if valid read transfer
                else if (valid == 1'b1 && hwrite == 1'b1)
                    next_state = wwait;                   // Move to write wait state if valid write transfer
            end

            read: begin                                   // Read setup phase
                psel = 1'b1;                              // Select APB peripheral
                paddr = haddr;                            // Pass AHB address to APB
                pwrite = 1'b0;                            // Set APB for read operation
                hready = 1'b0;                            // AHB must wait (bridge busy)

                next_state = renable;                     // Move to APB enable phase for read
            end

            renable: begin                                // APB Read enable phase
                penable = 1'b1;                           // APB enable phase (transaction completes here)
                hrdata = prdata;                          // Capture APB read data to AHB
                hready = 1'b1;                            // AHB is now ready for next transaction

                if (valid == 1'b0)
                    next_state = idle;                    // Go to idle if no new transfer
                else if (valid == 1'b1 && hwrite == 1'b0)
                    next_state = read;                    // Go to read if new read transaction
                else if (valid == 1'b1 && hwrite == 1'b1)
                    next_state = wwait;                   // Go to write wait if new write transaction
            end

            wwait: begin                                  // Write wait state (latch address and data)
                haddr_temp = haddr;                       // Save AHB address
                hwdata_temp = hwdata;                     // Save AHB write data

                if (valid == 1'b0)
                    next_state = write;                   // Go to write setup if no new transfer
                else if (valid == 1'b1)
                    next_state = write_p;                 // Go to pipelined write if new transfer exists
            end

            write: begin                                  // APB Write setup phase
                psel = 1'b1;                              // Select APB peripheral
                paddr = haddr_temp;                       // Send saved AHB address to APB
                pwdata = hwdata_temp;                     // Send saved AHB write data to APB
                pwrite = 1'b1;                            // Set APB for write operation
                hready = 1'b0;                            // AHB must wait (bridge busy)

                if (valid == 1'b0)
                    next_state = wenable;                 // Go to write enable if no pipelined transfer
                else if (valid == 1'b1)
                    next_state = wenable_p;               // Go to pipelined write enable if new transfer
            end

            write_p: begin                                // Pipelined APB Write setup phase
                psel = 1'b1;                              // Select APB peripheral
                paddr = haddr_temp;                       // Send saved AHB address to APB
                pwdata = hwdata_temp;                     // Send saved AHB write data to APB
                pwrite = 1'b1;                            // Set APB for write operation
                hready = 1'b0;                            // AHB must wait (bridge busy)

                next_state = wenable_p;                   // Move to pipelined write enable phase
            end

            wenable: begin                                // APB Write enable phase (normal)
                penable = 1'b1;                           // APB enable phase: transaction completes now
                hready = 1'b1;                            // AHB ready for next transfer

                if (valid == 1'b1 && hwrite == 1'b0)
                    next_state = read;                    // If new read → Go to read
                else if (valid == 1'b1 && hwrite == 1'b1)
                    next_state = wwait;                   // If new write → Go to write wait
                else if (valid == 1'b0)
                    next_state = idle;                    // If no new transfer → Go to idle
            end

            wenable_p: begin                              // APB Write enable phase (pipelined)
                penable = 1'b1;                           // APB enable phase: transaction completes now
                hready = 1'b1;                            // AHB ready for next transfer

                if (valid == 1'b0 && hwrite == 1'b1)
                    next_state = write;                   // No new valid transfer → Go to write
                else if (valid == 1'b1 && hwrite == 1'b1)
                    next_state = write_p;                 // New pipelined write → Go to write_p
                else if (hwrite == 1'b0)
                    next_state = read;                    // If new read → Go to read
            end

            default: next_state = idle;                   // Safe fallback to idle
        endcase
    end

endmodule
