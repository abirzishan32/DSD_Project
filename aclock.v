module aclock (
    input reset,        // Global active-high reset signal to initialize the system
    input clk,          // Master clock input (runs fast, source for internal timing)
    input [1:0] H_in1,  // 2-bit input: Tens digit of the Hour (Values: 0-2)
    input [3:0] H_in0,  // 4-bit input: Ones digit of the Hour (Values: 0-9)
    input [3:0] M_in1,  // 4-bit input: Tens digit of the Minute (Values: 0-5)
    input [3:0] M_in0,  // 4-bit input: Ones digit of the Minute (Values: 0-9)
    input LD_time,      // Control signal: Load Time
                        // If High (1), loads the switch inputs (H_in, M_in) into Current Time registers
    input LD_alarm,     // Control signal: Load Alarm
                        // If High (1), loads the switch inputs (H_in, M_in) into Alarm registers
    input STOP_al,      // Button input: Stop Alarm
                        // If High (1), turns off the ringing alarm (resets Alarm output)
    input AL_ON,        // Switch input: Alarm Enable
                        // If High (1), the alarm feature is active and can trigger
    output reg Alarm,   // Output signal: High when the current time matches the alarm time
    output [1:0] H_out1, // Output: Tens digit of current Hour (for 7-segment display or similar)
    output [3:0] H_out0, // Output: Ones digit of current Hour
    output [3:0] M_out1, // Output: Tens digit of current Minute
    output [3:0] M_out0  // Output: Ones digit of current Minute
);

    //*************** Internal Registers & Wires ***************//
    
    // Clock generation registers
    reg clk_1s;       // Generated 1-second clock pulse (derived from master clk)
    reg [3:0] tmp_1s; // Counter used to divide the input clk frequency down to 1Hz

    // Timekeeping registers (Internal Binary Representation)
    // These store the actual time values. 'tmp_second' is kept for counting up minutes.
    reg [5:0] tmp_hour, tmp_minute, tmp_second; 
    
    // Display registers (Binary-Coded Decimal / Digit Separation)
    // 'c_' prefix = Current Time components
    // 'a_' prefix = Alarm Time components
    reg [1:0] c_hour1, a_hour1; // Tens digit of Hour
    reg [3:0] c_hour0, a_hour0; // Ones digit of Hour
    reg [3:0] c_min1, a_min1;   // Tens digit of Minute
    reg [3:0] c_min0, a_min0;   // Ones digit of Minute
    
    // Helper function: Modulo 10 calculation
    // Used to extract the tens digit from a 2-digit number (e.g., 45 -> 4)
    // Logic: maps logic ranges to integer values 0-5
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

    //*************** Main Timekeeping & Control Logic ***************//
    // Triggered on the rising edge of the 1-second clock OR asynchronous reset
    always @(posedge clk_1s or posedge reset) begin
        if (reset) begin
            // --- Reset Condition ---
            // Clear Alarm registers
            a_hour1 <= 2'b00;
            a_hour0 <= 4'b0000;
            a_min1 <= 4'b0000;
            a_min0 <= 4'b0000;
            
            // Initialize Current Time registers based on inputs
            // Converts discrete digit inputs back to binary integer for counting
            tmp_hour <= H_in1 * 10 + H_in0;
            tmp_minute <= M_in1 * 10 + M_in0;
            tmp_second <= 0; // Start seconds at 0
        end 
        else begin
            // --- Normal Operation ---
            
            // 1. Alarm Setting Mode
            // If LD_alarm is active, update Alarm registers from inputs
            if (LD_alarm) begin
                a_hour1 <= H_in1;
                a_hour0 <= H_in0;
                a_min1 <= M_in1;
                a_min0 <= M_in0;
            end
            
            // 2. Time Setting Mode
            // If LD_time is active, update Current Time from inputs
            if (LD_time) begin
                tmp_hour <= H_in1 * 10 + H_in0;
                tmp_minute <= M_in1 * 10 + M_in0;
                tmp_second <= 0; // Reset seconds when manually setting time
            end 
            else begin
                // 3. Time Increment Logic
                // Increment internal seconds counter
                tmp_second <= tmp_second + 1;
                
                // Check for Second Overflow (>= 59)
                if (tmp_second >= 59) begin
                    tmp_minute <= tmp_minute + 1; // Increment Minute
                    tmp_second <= 0;              // Reset Second
                    
                    // Check for Minute Overflow (>= 59)
                    if (tmp_minute >= 59) begin
                        tmp_minute <= 0;          // Reset Minute
                        tmp_hour <= tmp_hour + 1; // Increment Hour
                        
                        // Check for Day Overflow (>= 24 Hours)
                        if (tmp_hour >= 24) begin
                            tmp_hour <= 0; // Reset Hour to 0 (Midnight)
                        end
                    end
                end
            end
        end
    end

    //*************** Clock Divider Logic ***************//
    // Converts input 'clk' to a 1Hz 'clk_1s' signal
    // This divider counts to 10 (0-9). 
    // This assumes input 'clk' is 10Hz. Validates on rising edge of clk or reset.
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            tmp_1s <= 0;
            clk_1s <= 0;
        end 
        else begin
            tmp_1s <= tmp_1s + 1; // Increment divider counter
            
            // Generate Clock Pulse with ~50% Duty Cycle
            if (tmp_1s <= 5)
                clk_1s <= 0; // Low for first half
            else if (tmp_1s >= 10) begin
                clk_1s <= 1; // High 
                tmp_1s <= 1; // Reset counter to 1 (adjust cycle length)
            end 
            else
                clk_1s <= 1; // High for second half
        end
    end

    //*************** Output Display Logic ***************//
    // Combinational logic block to convert binary time to digit segments
    always @(*) begin
        // --- Calculate Hour Digits ---
        // Determine Tens digit for Hour
        if (tmp_hour >= 20) begin
            c_hour1 = 2;
        end 
        else begin
            if (tmp_hour >= 10)
                c_hour1 = 1;
            else
                c_hour1 = 0;
        end
        // Determine Ones digit for Hour (Total - Tens*10)
        c_hour0 = tmp_hour - c_hour1 * 10;
        
        // --- Calculate Minute Digits ---
        c_min1 = mod_10(tmp_minute);        // Tens digit using helper function
        c_min0 = tmp_minute - c_min1 * 10;  // Ones digit
    end

    // --- Assign Outputs ---
    assign H_out1 = c_hour1;
    assign H_out0 = c_hour0;
    assign M_out1 = c_min1;
    assign M_out0 = c_min0;

    //*************** Alarm Trigger Logic ***************//
    // Checks if Current Time matches Alarm Time
    always @(posedge clk_1s or posedge reset) begin
        if (reset)
            Alarm <= 0;
        else begin
            // Compare Hours and Minutes Digits
            // Concatenates digits to form a single comparison vector
            if ({a_hour1, a_hour0, a_min1, a_min0} == {c_hour1, c_hour0, c_min1, c_min0}) begin
                if (AL_ON) // Check if Alarm Switch is Enabled
                    Alarm <= 1;
            end
            
            // Turn off alarm if STOP button is pressed
            if (STOP_al) 
                Alarm <= 0;
        end
    end

endmodule