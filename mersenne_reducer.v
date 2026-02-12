// Mersenne Reducer: Fast Modular Reduction for 2^p - 1
// NO division or modulo operators - pure bit manipulation!
//
// Algorithm: x mod (2^p - 1) = (x & mask) + (x >> p)
// Iterate until result < 2^p - 1
//
// Critical: This runs in O(1) hardware cycles vs software O(n) division

module mersenne_reducer #(
    parameter P = 13,           // Mersenne exponent (M_p = 2^P - 1)
    parameter WIDTH = 2*P       // Input width (enough for squared values)
)(
    input  wire clk,
    input  wire rst_n,
    input  wire valid_in,       // Start reduction
    input  wire [WIDTH-1:0] x,  // Input value
    output reg  [P-1:0] result, // Reduced result (< 2^P - 1)
    output reg  valid_out       // Output ready
);

    localparam MERSENNE = (1 << P) - 1;  // 2^P - 1

    // State machine for iterative reduction (Verilog-2005)
    localparam IDLE   = 2'b00;
    localparam REDUCE = 2'b01;
    localparam FINAL  = 2'b10;

    reg [1:0] state, next_state;

    reg [WIDTH-1:0] temp;       // Temporary accumulator
    reg [P-1:0] low, high_sum;
    reg [3:0] cycle_count;      // Reduction iterations

    // Combinational reduction logic (simplified for Verilog-2005)
    always @(*) begin
        low = temp[P-1:0];              // Lower P bits
        high_sum = temp[WIDTH-1:P];     // Upper bits (simplified)
    end

    // State transition
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            temp <= 0;
            result <= 0;
            valid_out <= 0;
            cycle_count <= 0;
        end else begin
            state <= next_state;
            valid_out <= 0;  // Default

            case (state)
                IDLE: begin
                    if (valid_in) begin
                        temp <= x;
                        cycle_count <= 0;
                    end
                end

                REDUCE: begin
                    temp <= low + high_sum;
                    cycle_count <= cycle_count + 1;
                end

                FINAL: begin
                    // Final adjustment: if result >= MERSENNE, subtract it
                    if ((low + high_sum) >= MERSENNE)
                        result <= (low + high_sum) - MERSENNE;
                    else
                        result <= low + high_sum;
                    valid_out <= 1;
                end
            endcase
        end
    end

    // Next state logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:
                if (valid_in) next_state = REDUCE;

            REDUCE: begin
                // Check if we need more reduction (result still > P bits)
                if ((low + high_sum) < (1 << P))
                    next_state = FINAL;
                else if (cycle_count >= 4)  // Safety limit
                    next_state = FINAL;
                // else stay in REDUCE
            end

            FINAL:
                next_state = IDLE;
        endcase
    end

endmodule


// Fast single-cycle variant (combinational only, no FSM)
module mersenne_reducer_comb #(
    parameter P = 13,
    parameter WIDTH = 2*P
)(
    input  wire [WIDTH-1:0] x,
    output wire [P-1:0] result
);

    localparam MERSENNE = (1 << P) - 1;

    wire [P:0] stage1, stage2, stage3;

    // Stage 1: Split and add
    assign stage1 = x[P-1:0] + x[WIDTH-1:P];

    // Stage 2: Reduce if needed
    assign stage2 = (stage1 >= (1<<P)) ? (stage1[P-1:0] + stage1[P]) : stage1;

    // Stage 3: Final correction
    assign stage3 = (stage2 >= MERSENNE) ? (stage2 - MERSENNE) : stage2;

    assign result = stage3[P-1:0];

endmodule
