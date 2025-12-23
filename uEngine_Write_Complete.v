`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    02:02:31 06/17/2014 
// Design Name: 
// Module Name:    uEngine_Write_Complete 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module uEngine_Write_Complete(
	 input  SysClock,
	 output reg ModuleDone = 1'b0,
	 input  ModuleStart,
	 output reg [31:0]SPI_TX = 32'b0,
	 output reg SPI_START = 1'b0,
	 input  SPI_DONE,
	 input  [15:0]EngineMap,
	 input  [2:0]ActualChipIndex,
	 input  [15:0]Register0Default
    );

// Variables
reg [3:0]MainMachineState = 4'b0;
reg [2:0]SupervisorState = 3'b0;
reg [7:0]ProgressCounter = 8'b0;

// The Main Machine
always @(posedge SysClock)
begin
	if (SupervisorState == 3'b000)
	begin
		MainMachineState <= 4'b0;
		ProgressCounter <= 8'b0;
		ModuleDone <= 1'b0;
		SPI_TX <= 32'b0;
		SupervisorState <= ((ModuleStart == 1'b1) && (ModuleDone == 1'b0)) ? 3'b001 : 3'b000;
	end
	else
	begin
		// Loop Variable2 is used as our monitor. Loop-Variable is used are Engine Address
		if (MainMachineState == 4'b0000)
		begin			
		
			// Has Engine Address overflown? 
			if (ProgressCounter == 8'b01000000) // Here, we use Inverse of Bit-5 for Read-Complete
			begin
				// We have finished scanning. Proceed to the next stage, which is ATTEMPTING to load Job1 to the tile, if it exists there
				ProgressCounter <= 8'b0;
				ModuleDone <= 1'b1;	
				SupervisorState <= 3'b000;
				MainMachineState <= 4'b0000;
				SPI_TX <= 32'b0;
			end
			else
			begin
				// Local Variable
				SupervisorState <= 3'b001;

				// Set proper data as well
				SPI_TX	<= {1'b0, // WRITE OPERATION 
								 ActualChipIndex[2:0], ProgressCounter[3:0], // CHIP ADDRESS (3Bit), ENGINE ADDRESS (4Bit) 
								 8'b0, // Address of the register 
								 Register0Default[15:13], 
								 ~ProgressCounter[4] & (~ProgressCounter[5]) , // RESET BIT
								 ~ProgressCounter[4] & (ProgressCounter[5]), // !WRITE COMPLETE 
								 1'b0 , //  READ COMPLETE , For the first 16 runs, this bit will be set. For the second 16 runs, it'll be zero
								 1'b0, // !RESET SPI ERROR
								 Register0Default[8:0]};	// 9 Bits
  
				// Go to next step. That's where we start the engine
				MainMachineState <= 4'b0001;
			end
		end
		else if (MainMachineState == 4'b0001)
		begin
			// Local Variable
			SupervisorState <= 3'b001;
			SPI_TX <= SPI_TX;
			
			// Start SPI engine
			SPI_START <= 1'b1;
			MainMachineState <= 4'b0010;				
		end
		else if (MainMachineState == 4'b0010)
		begin
			// Local Variable
			SupervisorState <= 3'b001;		
			SPI_TX <= SPI_TX;
		
			// Start SPI engine
			SPI_START <= 1'b0;
			
			// Check SPI Egnein status
			if (SPI_DONE == 1)
			begin
				MainMachineState <= 4'b0011;
			end
			else
			begin
				MainMachineState <= 4'b0010;
			end				
		end
		else if (MainMachineState == 4'b0011)
		begin
			// Local Variable
			SupervisorState <= 3'b001;
			SPI_TX <= SPI_TX;
				
			// We have the result. See if the engine has finished
			ProgressCounter <= ProgressCounter+ 8'b000001;
			MainMachineState <= 4'b0000;
		end		
	end
end


endmodule
