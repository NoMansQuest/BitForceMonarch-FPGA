`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 	 Butterfly Labs
// Engineer: 	 Nasser Ghoseiri
// 
// Create Date:  02:03:42 06/17/2014 	
// Module Name:  uEngine_Job_Issuance 
// Project Name: BitForce Monarch
// Target Devices: XC6S75-T 
//////////////////////////////////////////////////////////////////////////////////
module uEngine_Job_Issuance(
	 input  SysClock,
	 output ModuleDone,
	 input  ModuleStart,
	 output [31:0]SPI_TX,
	 output SPI_START,
	 input  SPI_DONE,
	 input  [15:0]EngineMap,
	 input  [2:0]ActualChipIndex,
	 input  [31:0]Memory_ReadData,
	 output reg [8:0]Memory_Address = 9'b0,
	 output Memory_WriteEnable,
	 input  JobIndexToLoad,
	 output [15:0]DebugExport
);


// Our main machine...
parameter STATE_WAITING_FOR_COMMAND = 5'b00000;
parameter STATE_INITIALIZE = 5'b00001;
parameter STATE_ENGINE_LOAD_DATA_TO_SPI = 5'b00010;
parameter STATE_START_SPI = 5'b00011;
parameter STATE_WAIT_SPI_FINISH = 5'b00100;
parameter STATE_WAIT_POST_SPI_TRANSACTION = 5'b00101;
parameter STATE_WAIT_POST2_SPI_TRANSACTION = 5'b00110;

// Variables
reg [4:0]MainMachineState = 5'b0;
reg SignalJobDispatch 	  = 1'b0;
assign Memory_WriteEnable = 1'b0;

// Tile Job-Loading Variables
reg [7:0]STAGE_LOAD_TILE_SPI_Engine_Memory_Address = 8'b000000; // Used as a loop variable
reg [3:0]STAGE_LOAD_TILE_Master_State= 4'b0; 
reg [3:0]STAGE_LOAD_TILE_Engine_Index = 4'b0; 
reg [3:0]STAGE_LOAD_TILE_Loading_State = 4'b0; 
reg STAGE_LOAD_TILE_Double_Loading = 1'b0;

assign DebugExport = {26'b0, MainMachineState, SPI_DONE};

// Some wires...
wire [8:0]MEMORY_ADDRESS_JOB1_INFO_MIDSTATE  = {ActualChipIndex, 6'd3};
wire [8:0]MEMORY_ADDRESS_JOB1_INFO_MERKEL	   = {ActualChipIndex, 6'd11};
wire [8:0]MEMORY_ADDRESS_JOB2_INFO_MIDSTATE  = {ActualChipIndex, 6'd14};
wire [8:0]MEMORY_ADDRESS_JOB2_INFO_MERKEL	   = {ActualChipIndex, 6'd22};


// When to start SPI Transaction
wire bActivateSPIStart = (MainMachineState == STATE_START_SPI) ? 1'b1 : 1'b0;


wire bResetEngineIndex = (MainMachineState == STATE_WAITING_FOR_COMMAND) ? 1'b1 : 1'b0;
wire bIncrementEngineIndex = ((MainMachineState == STATE_WAIT_POST_SPI_TRANSACTION) && 
									  (STAGE_LOAD_TILE_Double_Loading == 1'b1)) ? 1'b1 : 1'b0;


wire bResetMemoryAddress = (MainMachineState == STATE_WAITING_FOR_COMMAND) ? 1'b1 : 1'b0;
wire bIncrementMemoryAddress = ((MainMachineState == STATE_WAIT_POST_SPI_TRANSACTION) && 
									    (STAGE_LOAD_TILE_Double_Loading == 1'b1) && 
									    (STAGE_LOAD_TILE_Engine_Index == 4'd15)) ? 1'b1 : 1'b0;


wire bResetSPIAddress =     (MainMachineState == STATE_WAITING_FOR_COMMAND) ? 1'b1 : 1'b0;
wire bIncrementSPIAddress = ((MainMachineState == STATE_WAIT_POST_SPI_TRANSACTION) && 
									 (STAGE_LOAD_TILE_Double_Loading == 1'b1) && 
									 (STAGE_LOAD_TILE_Engine_Index == 4'd15)) ? 1'b1 : 1'b0;


wire bResetDoubleLoading = (MainMachineState == STATE_WAITING_FOR_COMMAND);
wire bFlipDoubleLoading  = (MainMachineState == STATE_WAIT_POST_SPI_TRANSACTION);


// Different Assignments
assign SPI_TX  = {1'b0, ActualChipIndex[2:0], STAGE_LOAD_TILE_Engine_Index[3:0], // CHIP ADDRESS (3Bit), ENGINE ADDRESS (4Bit) 
		 			  {STAGE_LOAD_TILE_SPI_Engine_Memory_Address[7:1], STAGE_LOAD_TILE_Double_Loading}, // Address of the register 
					  (STAGE_LOAD_TILE_Double_Loading == 1'b0) ? Memory_ReadData[31:16] : Memory_ReadData[15:0]};	// 9 Bits	

always @(posedge SysClock)
begin
	if (bResetDoubleLoading)
	begin
		STAGE_LOAD_TILE_Double_Loading <= 1'b0;
	end
	else
	begin
		if (bFlipDoubleLoading)
		begin
			STAGE_LOAD_TILE_Double_Loading <= ~STAGE_LOAD_TILE_Double_Loading;
		end
		else
		begin
			STAGE_LOAD_TILE_Double_Loading <= STAGE_LOAD_TILE_Double_Loading;
		end
	end
end


always @(posedge SysClock)
begin
	if (bResetEngineIndex)
	begin
		STAGE_LOAD_TILE_Engine_Index <= 4'b0;
	end
	else
	begin
		if (bIncrementEngineIndex)
		begin
			STAGE_LOAD_TILE_Engine_Index <= STAGE_LOAD_TILE_Engine_Index + 4'b1;
		end
		else
		begin
			STAGE_LOAD_TILE_Engine_Index <= STAGE_LOAD_TILE_Engine_Index;	
		end
	end
end


always @(posedge SysClock)
begin
	if (bResetSPIAddress)
	begin
		STAGE_LOAD_TILE_SPI_Engine_Memory_Address <= 8'h80;
	end
	else
	begin
		if (bIncrementSPIAddress)
		begin
			STAGE_LOAD_TILE_SPI_Engine_Memory_Address <= (STAGE_LOAD_TILE_SPI_Engine_Memory_Address == 8'h8E) ? (8'hA0) : (STAGE_LOAD_TILE_SPI_Engine_Memory_Address + 8'd02);		
		end
		else
		begin
			STAGE_LOAD_TILE_SPI_Engine_Memory_Address <= STAGE_LOAD_TILE_SPI_Engine_Memory_Address;
		end
	end	
end

always @(posedge SysClock)
begin
	if (bResetMemoryAddress)
	begin
		Memory_Address <= (JobIndexToLoad == 0) ? MEMORY_ADDRESS_JOB1_INFO_MIDSTATE : MEMORY_ADDRESS_JOB2_INFO_MIDSTATE;
	end
	else
	begin
		if (bIncrementMemoryAddress)
		begin
			Memory_Address <= Memory_Address + 1;
		end
		else
		begin
			Memory_Address <= Memory_Address;
		end
	end
end

// When are we done? We're done when SPI_Memory reaches 0xA6
assign ModuleDone = (STAGE_LOAD_TILE_SPI_Engine_Memory_Address == 8'hA6) ? 1'b1 : 1'b0;
assign SPI_START = ((MainMachineState == STATE_START_SPI) ? 1'b1 : 1'b0);

always @(posedge SysClock)
begin

	case (MainMachineState)
		
		// Here we wait for the "START" command to arrive
		STATE_WAITING_FOR_COMMAND: begin
			MainMachineState <= (ModuleStart == 1'b1) ? STATE_INITIALIZE : STATE_WAITING_FOR_COMMAND;
		end
				
		// Here we are initializing, and move to next step
		STATE_INITIALIZE: begin
			MainMachineState <= STATE_ENGINE_LOAD_DATA_TO_SPI;
		end
				
		// Here we prepare SPI Data
		STATE_ENGINE_LOAD_DATA_TO_SPI: begin
			MainMachineState <= STATE_START_SPI;
		end
				
		// We go to waiting stage
		STATE_START_SPI: begin
			MainMachineState <= STATE_WAIT_SPI_FINISH;
		end
		
		// Wait for SPI to be done
		STATE_WAIT_SPI_FINISH: begin
			if (SPI_DONE == 1'b0)
			begin
				MainMachineState <= STATE_WAIT_SPI_FINISH;
			end
			else
			begin
				MainMachineState <= STATE_WAIT_POST_SPI_TRANSACTION;
			end
		end		
		
		STATE_WAIT_POST_SPI_TRANSACTION: begin
			MainMachineState <= STATE_WAIT_POST2_SPI_TRANSACTION;
		end		
		
		STATE_WAIT_POST2_SPI_TRANSACTION: begin
			// Should we abort? If so, go back to the beginning. If not, 
			if (ModuleDone == 1'b1)
			begin
				MainMachineState <= STATE_WAITING_FOR_COMMAND;
			end
			else
			begin
				MainMachineState <= STATE_ENGINE_LOAD_DATA_TO_SPI;
			end
		end
		
	endcase
	
end


endmodule
