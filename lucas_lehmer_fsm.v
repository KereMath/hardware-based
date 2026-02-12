// Lucas-Lehmer Primality Test FSM
// Tests if M_p = 2^p - 1 is prime
//
// Algorithm:
//   s_0 = 4
//   s_i = (s_{i-1}^2 - 2) mod M_p  for i = 1 to p-2
//   M_p is prime iff s_{p-2} == 0
//
// Hardware Advantage: Uses bit-shift reduction instead of slow division!

module lucas_lehmer_fsm #(
    parameter P = 13                // Test M_13 = 2^13 - 1 = 8191
)(
    input  wire clk,
    input  wire rst_n,
    input  wire start,              // Begin primality test
    output reg  is_prime,           // Result: 1 if M_p is prime
    output reg  done,               // Test completed
    output reg  [15:0] cycles       // Clock cycles consumed
);

    localparam MERSENNE = (1 << P) - 1;
    localparam ITERATIONS = P - 2;

    localparam IDLE   = 3'b000;
    localparam INIT   = 3'b001;
    localparam SQUARE = 3'b010;
    localparam REDUCE = 3'b011;
    localparam CHECK  = 3'b100;
    localparam FINISH = 3'b101;

    reg [2:0] state;

    reg [P-1:0] s;                  // Current Lucas-Lehmer value
    reg [2*P-1:0] s_squared;        // s^2 (needs 2P bits)
    reg [2*P-1:0] s_squared_minus_2;
    reg [P-1:0] s_reduced;          // After modular reduction
    reg [15:0] iteration;

    // Mersenne reducer instance (combinational for speed)
    wire [P-1:0] reducer_out;
    mersenne_reducer_comb #(.P(P), .WIDTH(2*P)) reducer (
        .x(s_squared_minus_2),
        .result(reducer_out)
    );

    // FSM logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            s <= 0;
            iteration <= 0;
            is_prime <= 0;
            done <= 0;
            cycles <= 0;
        end else begin
            case (state)
                IDLE: begin
                    done <= 0;
                    cycles <= 0;
                    if (start) begin
                        state <= INIT;
                        iteration <= 0;
                        cycles <= cycles + 1;
                    end
                end

                INIT: begin
                    s <= 4;                     // s_0 = 4
                    state <= SQUARE;
                    cycles <= cycles + 1;
                end

                SQUARE: begin
                    s_squared <= s * s;         // Hardware multiplier
                    s_squared_minus_2 <= (s * s) - 2;  // Prepare for reducer
                    state <= REDUCE;
                    cycles <= cycles + 1;
                end

                REDUCE: begin
                    s_reduced <= reducer_out;   // Combinational reduction
                    s <= reducer_out;
                    state <= CHECK;
                    cycles <= cycles + 1;
                end

                CHECK: begin
                    iteration <= iteration + 1;
                    if (iteration >= ITERATIONS - 1) begin
                        state <= FINISH;
                    end else begin
                        state <= SQUARE;        // Next iteration
                    end
                    cycles <= cycles + 1;
                end

                FINISH: begin
                    is_prime <= (s == 0);       // Prime if s_{p-2} == 0
                    done <= 1;
                    state <= IDLE;
                    cycles <= cycles + 1;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule


// Top-level wrapper with multiple exponent testing
module mersenne_prime_tester (
    input  wire clk,
    input  wire rst_n,
    input  wire start,
    input  wire [7:0] exponent,     // Which exponent to test
    output reg  is_prime,
    output reg  done,
    output reg  [15:0] cycles
);

    // Instantiate testers for common exponents
    wire done_13, done_17, done_19;
    wire prime_13, prime_17, prime_19;
    wire [15:0] cycles_13, cycles_17, cycles_19;

    lucas_lehmer_fsm #(.P(13)) test_13 (
        .clk(clk), .rst_n(rst_n),
        .start(start && exponent == 13),
        .is_prime(prime_13), .done(done_13), .cycles(cycles_13)
    );

    lucas_lehmer_fsm #(.P(17)) test_17 (
        .clk(clk), .rst_n(rst_n),
        .start(start && exponent == 17),
        .is_prime(prime_17), .done(done_17), .cycles(cycles_17)
    );

    lucas_lehmer_fsm #(.P(19)) test_19 (
        .clk(clk), .rst_n(rst_n),
        .start(start && exponent == 19),
        .is_prime(prime_19), .done(done_19), .cycles(cycles_19)
    );

    wire done_31, prime_31;
    wire [15:0] cycles_31;

    lucas_lehmer_fsm #(.P(31)) test_31 (
        .clk(clk), .rst_n(rst_n),
        .start(start && exponent == 31),
        .is_prime(prime_31), .done(done_31), .cycles(cycles_31)
    );

    // Multiplex outputs
    always @(*) begin
        case (exponent)
            13: begin
                is_prime = prime_13;
                done = done_13;
                cycles = cycles_13;
            end
            17: begin
                is_prime = prime_17;
                done = done_17;
                cycles = cycles_17;
            end
            19: begin
                is_prime = prime_19;
                done = done_19;
                cycles = cycles_19;
            end
            31: begin
                is_prime = prime_31;
                done = done_31;
                cycles = cycles_31;
            end
            default: begin
                is_prime = 0;
                done = 0;
                cycles = 0;
            end
        endcase
    end

endmodule
