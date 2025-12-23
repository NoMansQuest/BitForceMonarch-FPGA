`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 	   Butterfly Labs
// Engineer: 	   Nasser Ghoseiri
// 
// Create Date:    00:40:23 03/02/2014 
// Module Name:    SPI-Engine 
// Project Name:   BitForce Monarch
// Target Devices: XC6SLX75-T
//////////////////////////////////////////////////////////////////////////////////
module SPI_Engine(
    clk_for_SPI,
	 SPI_CLOCK,
	 SPI_MISO,
	 SPI_MOSI,
	 SPI_NCS,
	 Tx_Data,
	 Rx_Data,
	 EngineStart,
	 EngineDone
);
	  
	input  clk_for_SPI; // Should be around 20MHz
	output SPI_CLOCK;
	input  SPI_MISO;
	output SPI_MOSI;
	output reg SPI_NCS = 1'b1;
	input  [31:0]Tx_Data;
	output reg [15:0]Rx_Data; 
	input	 EngineStart;
	output EngineDone;

	// Variables
	reg [31:0]Tx_Shifter = 32'b0;

	assign SPI_CLOCK = clk_for_SPI;
	assign SPI_MOSI = Tx_Shifter[31];
	
	// State-Machine
	reg [2:0]SPI_STATE = 3'b000;
	reg [4:0]SPI_COUNTER = 5'b00000;
	
	// Tx Control
	always @(negedge clk_for_SPI)
	begin
		if (SPI_STATE == 3'b000)
		begin
			Tx_Shifter <= Tx_Data;
		end
		else
		begin
			Tx_Shifter <= {Tx_Shifter[30:0], 1'b0}; // Perform the shift
		end
	end
	
	always @(posedge clk_for_SPI) 
	begin
		Rx_Data[15:0] <= (SPI_STATE == 3'b001) ? {Rx_Data[14:0], SPI_MISO} : Rx_Data;
	end
	
	assign EngineDone = (SPI_STATE[0] & SPI_STATE[1] & SPI_STATE[2]); // State = 3'b111 then we're done...
	
	always @(negedge clk_for_SPI)
	begin
		if (SPI_STATE == 3'b000)
		begin
			if (EngineStart)
			begin
				SPI_NCS <= 1'b0;
				SPI_STATE <= 3'b001;
				SPI_COUNTER <= 5'b0;
			end
			else
			begin
				SPI_NCS <= 1'b1;
				SPI_STATE <= 3'b000;
				SPI_COUNTER <= 5'b0;
			end
		end
		else if (SPI_STATE == 3'b001)
		begin
			if (SPI_COUNTER == 5'b11111)
			begin
				SPI_NCS <= 1'b1;
				SPI_STATE <= 3'b111;
			end
			else
			begin
				SPI_COUNTER <= SPI_COUNTER + 5'b00001;
			end
		end
		else 
		begin
			SPI_STATE <= (!EngineStart) ? 3'b0 : SPI_STATE; // Stay here until EngineStart is gone
			SPI_NCS <= 1'b1;
			SPI_COUNTER <= 5'b0;
		end		
	end
	


endmodule
