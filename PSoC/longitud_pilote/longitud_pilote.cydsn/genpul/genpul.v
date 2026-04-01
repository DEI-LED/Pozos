
//`#start header` -- edit after this line, do not edit this line
// ========================================
//
// Copyright YOUR COMPANY, THE YEAR
// All Rights Reserved
// UNPUBLISHED, LICENSED SOFTWARE.
//
// CONFIDENTIAL AND PROPRIETARY INFORMATION
// WHICH IS THE PROPERTY OF your company.
//
// ========================================
`include "cypress.v"
//`#end` -- edit above this line, do not edit this line
// Generated on 06/30/2025 at 10:37
// Component: genpul
module genpul (
	output  reg pulsos,
	input   clk,
	input   hab,
	input   rst
);
	parameter cant = 1024;
	parameter semiperiodo = 265;

//`#start body` -- edit after this line, do not edit this line

//        Your code goes here

   //parameter SEMI_PERIODO = 10'd265;    // semiperiodo para 90 kHz, hay que restar dos al valor real: 267 -2 = 265
   //localparam SEMI_PERIODO = 10'd5;    // semiperiodo de prueba para simulación
   
   localparam inic    = 3'b000;
   localparam en1     = 3'b001;
   localparam espera1 = 3'b010;
   localparam en0     = 3'b011;
   localparam espera0 = 3'b100;
   localparam hab_en1 = 3'b101;

   reg [2:0] est;    // Estado inicial
   reg [9:0] cont;
   reg [9:0] per; 
   //reg [9:0] cant_r = 10'd0;

   initial begin
      pulsos <= 1'b0;  // Inicializa la salida a 0
      est    <= inic;
      cont   <= 10'd0;
      per    <= 10'd0; 
   end

   always @(posedge clk)
      if (rst) begin
         est    <= inic;
         pulsos <= 0;
         cont   <= 10'd0;
         per    <= 10'd0; 
      end
      else
         case (est)
            inic : begin
               // transición
               if (hab == 0)
                  est <= inic;
               else 
                  if (cant == 0)
                     est <= inic;
                  else
                     est <= en1;
               // en el estado
               pulsos <= 0;
               cont   <= 0;
               per    <= 0;
            end
            en1 : begin
               // transición
               est <= espera1;
               // en el estado
               pulsos <= 1;
               cont   <= cont +1;
               per    <= 0;
            end
            espera1 : begin
               // transición
               if (per == semiperiodo)
                  est <= en0;
               else
                  est <= espera1;
               // en el estado
               per <= per +1;
            end
            en0 : begin
               // transición
               if (cont == cant)
                  if (hab == 0)
                     est <= inic;
                  else
                     est <= hab_en1;
               else
                  est <= espera0;
               // en el estado
               pulsos <= 0;
               per    <= 0;
            end
            espera0 : begin
               // transición
               if (per == semiperiodo)
                  est <= en1;
               else
                  est <= espera0;
               // en el estado
               per <= per +1;
            end
            hab_en1 : begin
               // transición
               if (hab == 0)
                  est <= inic;
               else
                  est <= hab_en1;
               // en el estado
               pulsos <= 0;
               cont   <= 0;
               per    <= 0;
            end
            default : begin  // Fault Recovery
               est    <= inic;
               pulsos <= 0;
               cont   <= 0;
               per    <= 0;
            end
         endcase


//`#end` -- edit above this line, do not edit this line
endmodule
//`#start footer` -- edit after this line, do not edit this line
//`#end` -- edit above this line, do not edit this line
