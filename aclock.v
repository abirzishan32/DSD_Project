module aclock (
    input reset,
    input clk,
    input [1:0] H_in1, // Most significant hour digit
    input [3:0] H_in0, // Least significant hour digit
    input [3:0] M_in1, // Most significant minute digit
    input [3:0] M_in0, // Least significant minute digit
    input LD_time,     // Load Time Control
    input LD_alarm,    // Load Alarm Control
    input STOP_al,     // Stop Alarm Button
    input AL_ON,       // Alarm Enable Switch
    output reg Alarm,
    output [1:0] H_out1,
    output [3:0] H_out0,
    output [3:0] M_out1,
    output [3:0] M_out0
);

    //*************** Internal Register ***************//
    reg clk_1s; // 1-second clock signal
    reg [3:0] tmp_1s; // divider counter
    reg [5:0] tmp_hour, tmp_minute, tmp_second; // Internal time counters
    
    // Display registers (Hours and Minutes only)
    reg [1:0] c_hour1, a_hour1;
    reg [3:0] c_hour0, a_hour0;
    reg [3:0] c_min1, a_min1;
    reg [3:0] c_min0, a_min0;
    
    // Helper function for digit splitting
    function [3:0] mod_10;
        input [5:0] number;
        begin
            mod_10 = (number >= 50) ? 5 : 
                     (number >= 40) ? 4 : 
                     (number >= 30) ? 3 : 
                     (number >= 20) ? 2 : 
                     (number >= 10) ? 1 : 0;
        end
    endfunction

    //*************** Main Timekeeping Logic ***************//
    always @(posedge clk_1s or posedge reset) begin
        if (reset) begin
            // Reset Alarm Registers
            a_hour1 <= 2'b00;
            a_hour0 <= 4'b0000;
            a_min1 <= 4'b0000;
            a_min0 <= 4'b0000;
            
            // Reset Time Registers from Input or Zero
            tmp_hour <= H_in1 * 10 + H_in0;
            tmp_minute <= M_in1 * 10 + M_in0;
            tmp_second <= 0;
        end 
        else begin
            // Set Alarm Mode
            if (LD_alarm) begin
                a_hour1 <= H_in1;
                a_hour0 <= H_in0;
                a_min1 <= M_in1;
                a_min0 <= M_in0;
            end
            
            // Set Time Mode
            if (LD_time) begin
                tmp_hour <= H_in1 * 10 + H_in0;
                tmp_minute <= M_in1 * 10 + M_in0;
                tmp_second <= 0;
            end 
            else begin
                // Normal Operation: Count Time
                // We still count seconds internally to know when a minute passes
                tmp_second <= tmp_second + 1;
                if (tmp_second >= 59) begin
                    tmp_minute <= tmp_minute + 1;
                    tmp_second <= 0;
                    if (tmp_minute >= 59) begin
                        tmp_minute <= 0;
                        tmp_hour <= tmp_hour + 1;
                        if (tmp_hour >= 24) begin
                            tmp_hour <= 0;
                        end
                    end
                end
            end
        end
    end

    //*************** Clock Divider (10Hz -> 1Hz) ***************//
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tmp_1s <= 0;
            clk_1s <= 0;
        end 
        else begin
            tmp_1s <= tmp_1s + 1;
            if (tmp_1s <= 5)
                clk_1s <= 0;
            else if (tmp_1s >= 10) begin
                clk_1s <= 1;
                tmp_1s <= 1;
            end 
            else
                clk_1s <= 1;
        end
    end

    //*************** Output Display Logic ***************//
    always @(*) begin
        // Split Hours
        if (tmp_hour >= 20) begin
            c_hour1 = 2;
        end 
        else begin
            if (tmp_hour >= 10)
                c_hour1 = 1;
            else
                c_hour1 = 0;
        end
        c_hour0 = tmp_hour - c_hour1 * 10;
        
        // Split Minutes
        c_min1 = mod_10(tmp_minute);
        c_min0 = tmp_minute - c_min1 * 10;
    end

    // Assign Outputs to Ports
    assign H_out1 = c_hour1;
    assign H_out0 = c_hour0;
    assign M_out1 = c_min1;
    assign M_out0 = c_min0;

    //*************** Alarm Trigger Logic ***************//
    always @(posedge clk_1s or posedge reset) begin
        if (reset)
            Alarm <= 0;
        else begin
            // Comparator: Only checks Hours and Minutes now
            if ({a_hour1, a_hour0, a_min1, a_min0} == {c_hour1, c_hour0, c_min1, c_min0}) begin
                if (AL_ON) 
                    Alarm <= 1;
            end
            
            if (STOP_al) 
                Alarm <= 0;
        end
    end

endmodule