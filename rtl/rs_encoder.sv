// Module: rs_encoder
// Function: Systematic RS Encoder
// Target Code: RS(15,11) over GF(16), p(x)=x⁴+x+1
// Author: H'ng Kean Teong

module rs_encoder #(
    parameter SYM_W = 4 // Symbol width
)
(
    //Clock and Reset
    input logic clk,
    input logic rst_n,

    //Data IN Interface
    input logic start,
    input logic [SYM_W-1:0] din,
    input logic din_valid,
    output logic din_ready,

    //Data OUT Interface
    output logic [SYM_W-1:0] dout,
    output logic dout_valid,
    input logic dout_ready,
    output logic parity_phase
);


localparam N = 15; // Codeword length
localparam K = 11; // Message length
localparam PAR_NUM = N - K; // Number of parity symbols


typedef enum logic [1:0] {
    IDLE,
    DATA,
    PARITY
} state_t;

state_t state, next_state;

logic [SYM_W-1:0] lfsr [PAR_NUM];

logic[$clog2(K)-1:0] sym_cnt;



function automatic logic [SYM_W-1:0] gf_mul3(input logic [SYM_W-1:0] a);

    gf_mul3[3] = a[2] ^ a[3];
    gf_mul3[2] = a[1] ^ a[2];
    gf_mul3[1] = a[0] ^ a[1] ^ a[3];
    gf_mul3[0] = a[0] ^ a[3];

endfunction

function automatic logic [SYM_W-1:0] gf_mul12(input logic [SYM_W-1:0] a);

    gf_mul12[3] = a[0] ^ a[1] ^ a[3];
    gf_mul12[2] = a[0] ^ a[2];
    gf_mul12[1] = a[1] ^ a[3];
    gf_mul12[0] = a[1] ^ a[2];

endfunction

function automatic logic [SYM_W-1:0] gf_mul15(input logic [SYM_W-1:0] a);

    gf_mul15[3] = a[0] ^ a[1] ^ a[2];
    gf_mul15[2] = a[0] ^ a[1];
    gf_mul15[1] = a[0];
    gf_mul15[0] = a[0] ^ a[1] ^ a[2] ^ a[3];

endfunction


logic [SYM_W-1:0] fb;
logic [SYM_W-1:0] lfsr_data_next [PAR_NUM];

always_comb begin
    fb = lfsr[PAR_NUM-1] ^ din;
    lfsr_data_next[3] = lfsr[2] ^ gf_mul15(fb);  // G3=15
    lfsr_data_next[2] = lfsr[1] ^ gf_mul3 (fb);  // G2=3
    lfsr_data_next[1] = lfsr[0] ^ fb;            // G1=1 → 直接 XOR fb,不用函数
    lfsr_data_next[0] = gf_mul12(fb);     // G0=12,R0 下面没寄存器,无 XOR 项

end

logic lfsr_load;    // 数据拍:载入 lfsr_data_next
logic lfsr_shift;   // 校验拍:移位

always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        for(int i=0; i<PAR_NUM; i++) begin
            lfsr[i] <= '0;
        end
    end
    else begin
        if(lfsr_load)begin
            lfsr[0] <= lfsr_data_next[0];
            lfsr[1] <= lfsr_data_next[1];
            lfsr[2] <= lfsr_data_next[2];
            lfsr[3] <= lfsr_data_next[3];
        end
        else if(lfsr_shift)begin
            lfsr[3] <= lfsr[2];
            lfsr[2] <= lfsr[1];
            lfsr[1] <= lfsr[0];
            lfsr[0] <= '0;
        end

    end

end


always_ff@(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        state <= IDLE;
    end
    else begin
        state <= next_state;
    end
end

always_comb begin
    next_state = state;
    lfsr_load = 1'b0;
    lfsr_shift = 1'b0;
    
    case(state)
        IDLE:begin
            if(start)begin
                next_state = DATA;
            end
        end

        DATA:begin
            lfsr_load = din_valid && dout_ready;
            if(lfsr_load)begin
                if(sym_cnt == K-1)begin
                    next_state = PARITY;
                end
            end
        end

        PARITY:begin
            lfsr_shift = dout_ready;
            if(lfsr_shift && sym_cnt == PAR_NUM-1)begin
                next_state = IDLE;
            end
        end

        default:begin
            next_state = IDLE;
        end

    endcase
end

always_ff @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        sym_cnt <= '0;
    end
    else begin
        case(state)
            IDLE:begin
                sym_cnt <= '0;
            end

            DATA:begin
                if(lfsr_load)begin
                    sym_cnt <= (sym_cnt == K-1) ? 0 : sym_cnt + 1'b1;
                end
            end

            PARITY:begin
                if(lfsr_shift)begin
                    sym_cnt <= (sym_cnt == PAR_NUM-1) ? '0 : sym_cnt + 1'b1;
                end
            end

            default:begin
                sym_cnt <= '0;
            end

        endcase
    end
end
    
assign din_ready    = (state == DATA) && dout_ready;       // 只在 DATA 收,且需下游有空位(透传)
assign dout         = (state == PARITY) ? lfsr[PAR_NUM-1] : din;     // 校验阶段吐 R3,否则透传 din
assign dout_valid   = (state == PARITY) ? 1'b1              // 校验阶段永远有货
                      : (state == DATA) ? din_valid         // 数据阶段:输入有效即输出有效
                      :                   1'b0;              // IDLE:无输出
assign parity_phase = (state == PARITY);





endmodule