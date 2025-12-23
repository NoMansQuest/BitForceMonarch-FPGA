`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    02:03:42 06/17/2014 
// Design Name: 
// Module Name:    uEngine_Engine_Status_Checker 
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
module uEngine_Engine_Status_Checker(
	 input SysClock,
	 input  ModuleStart,
	 output reg ModuleDone = 1'b0,
	 output reg [31:0]SPI_TX = 32'b0,
	 input  [15:0]SPI_RX,
	 output reg SPI_START = 1'b0,
	 input  SPI_DONE,
	 input  [15:0]EngineMap,
	 input  [2:0]ActualChipIndex,
	 output reg [4:0]TotalEnginesBusy = 5'b0,
	 output [31:0]DebugExport
    );

// Variables
reg [3:0]MainMachineState = 4'b0;
reg [2:0]SupervisorState = 3'b0;
reg [15:0]TempEngineMap = 16'b0;
reg [7:0]ProgressCounter = 8'b0;
reg [4:0]__InternalTotalEnginesBusy	= 5'b0;
assign DebugExport = {28'b0, MainMachineState};

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
		__InternalTotalEnginesBusy <= 5'b0;
		TempEngineMap <= EngineMap;
	end
	else
	begin
		// Loop Variable2 is used as our monitor. Loop-Variable is used are Engine Address
		if (MainMachineState == 4'b0000)
		begin				
			// Has Engine Address overflown? 
			if (ProgressCounter == 8'b10000)
			begin
				// We have finished scanning. Proceed to the next stage
				ModuleDone <= 1'b1;
				MainMachineState <= 4'b0000;
				ProgressCounter <= 4'b0000;
				SupervisorState <= 3'b000;
				TotalEnginesBusy <= __InternalTotalEnginesBusy;
			end
			else
			begin
				
				// Set proper data as well
				SPI_TX <= {1'b1, // Read OPERATION 
							  ActualChipIndex[2:0], ProgressCounter[3:0], // CHIP ADDRESS (3Bit), ENGINE ADDRESS (4Bit) 
							  8'b0, // Address of the register 
							  16'b0}; // The rest doesn't matter 
		  
				// Go to next step. That's where we start the engine
				MainMachineState <= (TempEngineMap[0] == 1'b1) ? 4'b0001 : 4'b0000;
				TempEngineMap <= {1'b0, TempEngineMap[15:1]};
				ProgressCounter <= ProgressCounter + {7'b0, ~TempEngineMap[0]};
				
			end
		end
		else if (MainMachineState == 4'b0001)
		begin
			// Start SPI engine
			SPI_START <= 1'b1;
			MainMachineState <= 4'b0010;				
		end
		else if (MainMachineState == 4'b0010)
		begin
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
			// We have the result. See if the engine has finished
			__InternalTotalEnginesBusy <= __InternalTotalEnginesBusy + ((SPI_RX[1] == 1'b1) ? 1'b1 : 1'b0);
			ProgressCounter <= ProgressCounter + 8'b000001;
			MainMachineState <= 4'b0000;
		end	
	end
end
endmodule
