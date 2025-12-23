`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    02:03:21 06/17/2014 
// Design Name: 
// Module Name:    uEngine_Nonce_Gathering 
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
module uEngine_Nonce_Gathering(
	 input SysClock,
	 input  ModuleStart,
	 output ModuleDone,
	 output [31:0]SPI_TX,
	 input  [15:0]SPI_RX,
	 output reg SPI_START = 1'b0,
	 input  SPI_DONE,
	 input  [15:0]EngineMap,
	 input  [2:0]ActualChipIndex,	
	 input  [31:0]Memory_ReadData,
	 output reg [31:0]Memory_WriteData = 32'b0,
	 output reg [8:0]Memory_Address = 9'b0,
	 output Memory_WriteEnable,
	 input  [8:0]Memory_Address_To_Start_Storing
    );

// Variables
reg [4:0]MainStateMachine = 5'b0;
reg [3:0]VAR_EngineIndex = 4'b0;
reg [7:0]VAR_FIFOAddress = 8'b0;
reg [3:0]VAR_FIFOIndex   = 4'b0;
reg [3:0]VAR_NonceCount  = 4'b0;
reg bSECOND_WORD_READ    = 1'b0;
reg [15:0]LatchedEngineMap = 16'b0;
reg [7:0]LatchedFIFOMap	= 8'b0;

// List of STATES
parameter STATE_WAITING_FOR_COMMAND = 5'b00000;
parameter STATE_INITIALIZE = 5'b00001;
parameter STATE_ATTEMPTING_REG0_READ = 5'b00010;
parameter STATE_SHIFT_ENGINE_MAP = 5'b00011;
parameter STATE_PREPARE_DATA_FOR_REG0 = 5'b00100;
parameter STATE_START_SPI_FOR_REG0 = 5'b00101;
parameter STATE_WAITING_COMPLETION_REG0 = 5'b00110;
parameter STATE_POST_PROCESS_REG0 = 5'b00111;
parameter STATE_POST2_PROCESS_REG0 = 5'b01000;
parameter STATE_ATTEMPTING_FIFO_READ = 5'b01001;
parameter STATE_PREPARE_FIFO_READ_DATA = 5'b01010;
parameter STATE_START_SPI_FIFO_READ = 5'b01011;
parameter STATE_WAITING_COMPLETION_FIFO_READ = 5'b01100;
parameter STATE_POST_PROCESSING_FIFO_READ = 5'b01101;
parameter STATE_POST_PROCESSING2_FIFO_READ = 5'b01110;
parameter STATE_SAVE_NONCE_COUNT_IN_MEMORY = 5'b01111;
parameter STATE_COMMIT_COUNT_TO_MEMORY = 5'b10000;
parameter STATE_MACHINE_ENDED = 5'b10001;

// Wires:
wire bREAD_ENGINES_FIFO = ((SPI_RX[15:8] != 8'b0) ? 1'b1 : 1'b0);
wire bSKIP_THIS_FIFO = (~LatchedFIFOMap[0]);
wire bREACHED_LAST_FIFO_INDEX = (VAR_FIFOIndex == 4'd7) ? 1'b1 : 1'b0;
wire bREACHED_LAST_ENGINE_INDEX = (VAR_EngineIndex == 4'd15) ? 1'b1 : 1'b0;

// Engine Map
wire bRightShiftEngineMap = (MainStateMachine == STATE_SHIFT_ENGINE_MAP) ? 1'b1 : 1'b0;
wire bLatchEngineMap = (MainStateMachine == STATE_INITIALIZE) ? 1'b1 : 1'b0;
wire bIS_ENGINE_VALID = LatchedEngineMap[0];

always @(posedge SysClock)
begin
	if (bLatchEngineMap)
	begin
		LatchedEngineMap <= EngineMap;
		VAR_EngineIndex <= 4'b0;
	end
	else
	begin
		if (bRightShiftEngineMap)
		begin
			LatchedEngineMap <= {1'b0, LatchedEngineMap[15:1]};
			VAR_EngineIndex <= VAR_EngineIndex + 4'b01;
		end
		else 
		begin
			LatchedEngineMap <= LatchedEngineMap;
			VAR_EngineIndex <= VAR_EngineIndex;
		end
	end
end

// FIFO Map
wire bRightShiftFIFOMap = ((MainStateMachine == STATE_POST_PROCESSING2_FIFO_READ) || 
								  ((MainStateMachine == STATE_PREPARE_FIFO_READ_DATA) && (bSKIP_THIS_FIFO))) ? 1'b1 : 1'b0;
								  
wire bLatchFIFOMap = (MainStateMachine == STATE_POST_PROCESS_REG0) ? 1'b1 : 1'b0;

always @(posedge SysClock)
begin
	if (bLatchFIFOMap)
	begin
		LatchedFIFOMap <= SPI_RX[15:8];
		VAR_FIFOIndex <= 3'b0;
		VAR_FIFOAddress <= 8'h80;
	end
	else
	begin
		if (bRightShiftFIFOMap)
		begin
			LatchedFIFOMap <= {1'b0, LatchedFIFOMap[7:1]};
			VAR_FIFOIndex <= VAR_FIFOIndex + 3'b001;
			VAR_FIFOAddress <= VAR_FIFOAddress + 8'd02;
		end
		else 
		begin
			LatchedFIFOMap <= LatchedFIFOMap;
			VAR_FIFOIndex <= VAR_FIFOIndex;
			VAR_FIFOAddress <= VAR_FIFOAddress;
		end
	end
end

// Nonce Count
wire bInitializeNonceCount = (MainStateMachine == STATE_WAITING_FOR_COMMAND) ? 1'b1 : 1'b0;
wire bIncrementNonceCount = (MainStateMachine == STATE_POST_PROCESSING2_FIFO_READ) ? 1'b1 : 1'b0;

always @(posedge SysClock)
begin
	if (bInitializeNonceCount)
	begin
		VAR_NonceCount <= 4'b0;
	end
	else
	begin
		if (bIncrementNonceCount == 1'b1)
		begin
			VAR_NonceCount <= VAR_NonceCount + 1;
		end
		else
		begin
			VAR_NonceCount <= VAR_NonceCount;
		end
	end
end	


// Second Word Read Handling
wire bFlipSecondWordRead = (MainStateMachine == STATE_POST_PROCESSING_FIFO_READ) ? 1'b1 : 1'b0;
wire bResetSecondWordRead = (MainStateMachine == STATE_WAITING_FOR_COMMAND) ? 1'b1 : 1'b0;

always @(posedge SysClock)
begin
	if (bResetSecondWordRead)
	begin
		bSECOND_WORD_READ <= 1'b0;
	end
	else if (bFlipSecondWordRead)
	begin
		bSECOND_WORD_READ <= ~bSECOND_WORD_READ;
	end
	else
	begin
		bSECOND_WORD_READ <= bSECOND_WORD_READ;
	end
end

// Memory Write-Data Handling
wire bLoadLowerHalfOfMemoryData = ((MainStateMachine == STATE_POST_PROCESSING_FIFO_READ) ? 1'b1 : 1'b0) & ~bSECOND_WORD_READ;
wire bLoadHigherHalfOfMemoryData = ((MainStateMachine == STATE_POST_PROCESSING_FIFO_READ) ? 1'b1 : 1'b0) & bSECOND_WORD_READ;
wire bLoadNonceCount = (MainStateMachine == STATE_SAVE_NONCE_COUNT_IN_MEMORY) ? 1'b1 : 1'b0;

assign Memory_WriteEnable = ((MainStateMachine == STATE_POST_PROCESSING2_FIFO_READ) || 
								  	  (MainStateMachine == STATE_COMMIT_COUNT_TO_MEMORY)) ? 1'b1 : 1'b0;

always @(posedge SysClock)
begin
	if (bLoadLowerHalfOfMemoryData == 1'b1)
	begin
		Memory_WriteData[15:0] <= SPI_RX[15:0];
	end
	else if (bLoadHigherHalfOfMemoryData == 1'b1)
	begin
		Memory_WriteData[31:16] <= SPI_RX[15:0];
	end
	else if (bLoadNonceCount == 1'b1)
	begin
		Memory_WriteData <= {28'b0, VAR_NonceCount};
	end
	else
	begin
		Memory_WriteData <= Memory_WriteData;
	end
end


wire bResetMemAddress = (MainStateMachine == STATE_WAITING_FOR_COMMAND) ? 1'b1 : 1'b0;
wire bIncrementMemAddress = (MainStateMachine == STATE_POST_PROCESSING2_FIFO_READ) ? 1'b1 : 1'b0;
wire bSavingNonceCountAddress = (MainStateMachine == STATE_SAVE_NONCE_COUNT_IN_MEMORY) ? 1'b1 : 1'b0;

always @(posedge SysClock)
begin
	if (bResetMemAddress)
	begin
		Memory_Address <= Memory_Address_To_Start_Storing;
	end
	else 
	begin
		if (bIncrementMemAddress)
		begin
			Memory_Address <= Memory_Address + 1;
		end
		else if (bSavingNonceCountAddress)
		begin
			Memory_Address <= Memory_Address_To_Start_Storing - 1;		
		end
		else
		begin
			Memory_Address <= Memory_Address;
		end	
	end
end


// Locked Engine Index
reg [3:0]VAR_LockedEngineIndex = 4'b0000;

always @(posedge SysClock)
begin
	if (MainStateMachine == STATE_WAITING_FOR_COMMAND)
	begin
		VAR_LockedEngineIndex <= 4'b0000;
	end
	else 
	begin
		if (MainStateMachine == STATE_SHIFT_ENGINE_MAP)
		begin
			VAR_LockedEngineIndex <= VAR_EngineIndex;
		end
		else
		begin
			VAR_LockedEngineIndex <= VAR_LockedEngineIndex;
		end		
	end
end

// SPI_TX assignment
wire bReadingRegister0 = (MainStateMachine < STATE_POST_PROCESS_REG0) ? 1'b1 : 1'b0;

assign SPI_TX = {1'b1, ActualChipIndex[2:0], VAR_LockedEngineIndex[3:0], (bReadingRegister0 == 1'b1) ? 8'b0 : {VAR_FIFOAddress[7:1], bSECOND_WORD_READ},16'b0};

// Module Done
assign ModuleDone = (MainStateMachine == STATE_MACHINE_ENDED) ? 1'b1 : 1'b0;

// Did we find all 8 nonces?
wire bFOUND_8_NONCES = (VAR_NonceCount == 4'd7) ? 1'b1 : 1'b0;

// Main State-Machine
always @(posedge SysClock)
begin
	case (MainStateMachine)
	
		STATE_WAITING_FOR_COMMAND: begin
			MainStateMachine <= (ModuleStart) ? STATE_INITIALIZE : STATE_WAITING_FOR_COMMAND;		
			SPI_START <= 1'b0;
		end		
		
		STATE_INITIALIZE: begin
			SPI_START <= 1'b0;
			MainStateMachine <= STATE_ATTEMPTING_REG0_READ;
		end
		
		STATE_ATTEMPTING_REG0_READ: begin
			MainStateMachine <= (bREACHED_LAST_ENGINE_INDEX) ? STATE_SAVE_NONCE_COUNT_IN_MEMORY : STATE_SHIFT_ENGINE_MAP;
			SPI_START <= 1'b0;
		end	

		// In this state, we right-shift our engines mape
		STATE_SHIFT_ENGINE_MAP: begin
			MainStateMachine <= (bIS_ENGINE_VALID) ? STATE_PREPARE_DATA_FOR_REG0 : STATE_ATTEMPTING_REG0_READ;
		end
		
		STATE_PREPARE_DATA_FOR_REG0: begin
			SPI_START <= 1'b0;
			MainStateMachine <= STATE_START_SPI_FOR_REG0;
		end		
		
		STATE_START_SPI_FOR_REG0: begin
			SPI_START <= 1'b1;
			MainStateMachine <= STATE_WAITING_COMPLETION_REG0;
		end		
		
		STATE_WAITING_COMPLETION_REG0: begin
			SPI_START <= 1'b0;
			MainStateMachine <= (SPI_DONE) ? STATE_POST_PROCESS_REG0 : STATE_WAITING_COMPLETION_REG0;
		end		
		
		STATE_POST_PROCESS_REG0: begin
			SPI_START <= 1'b0;
			MainStateMachine <= STATE_POST2_PROCESS_REG0;
		end		
		
		STATE_POST2_PROCESS_REG0: begin
			SPI_START <= 1'b0;
			MainStateMachine <= (bREAD_ENGINES_FIFO) ? STATE_PREPARE_FIFO_READ_DATA : STATE_ATTEMPTING_REG0_READ;		
		end		
		
		STATE_ATTEMPTING_FIFO_READ: begin
			SPI_START <= 1'b0;
			MainStateMachine <= (bREACHED_LAST_FIFO_INDEX) ? STATE_ATTEMPTING_REG0_READ : STATE_PREPARE_FIFO_READ_DATA;
		end		
		
		STATE_PREPARE_FIFO_READ_DATA: begin
			SPI_START <= 1'b0;
			MainStateMachine <= (bSKIP_THIS_FIFO) ? STATE_ATTEMPTING_FIFO_READ : STATE_START_SPI_FIFO_READ;
		end		
		
		STATE_START_SPI_FIFO_READ: begin
			SPI_START <= 1'b1;
			MainStateMachine <= STATE_WAITING_COMPLETION_FIFO_READ;
		end		
		
		STATE_WAITING_COMPLETION_FIFO_READ: begin
			SPI_START <= 1'b0;
			MainStateMachine <= (SPI_DONE) ? STATE_POST_PROCESSING_FIFO_READ : STATE_WAITING_COMPLETION_FIFO_READ;
		end		
		
		STATE_POST_PROCESSING_FIFO_READ: begin
			SPI_START <= 1'b0;
			MainStateMachine <= (bSECOND_WORD_READ) ? STATE_POST_PROCESSING2_FIFO_READ : STATE_PREPARE_FIFO_READ_DATA;
		end		
		
		// When we get to this stage, we ALSO need to increase Nonce-Count and save actual nonce to memory
		// BTW, If actual Nonce Count is 7, then after this stage it will become 8. So if it's 7, we have to move to nonce-saving part
		STATE_POST_PROCESSING2_FIFO_READ: begin
			SPI_START <= 1'b0;
			MainStateMachine <= (bFOUND_8_NONCES) ? STATE_SAVE_NONCE_COUNT_IN_MEMORY : STATE_ATTEMPTING_FIFO_READ;
		end			
		
		// Here we save the NonceCount in our little RAM
		STATE_SAVE_NONCE_COUNT_IN_MEMORY: begin
			SPI_START <= 1'b0;
			MainStateMachine <= STATE_COMMIT_COUNT_TO_MEMORY;
		end
		
		// This is the last state our in our game
		STATE_COMMIT_COUNT_TO_MEMORY: begin
			MainStateMachine <= STATE_MACHINE_ENDED; // We're done...
		end
		
		// This is just to set ModuleDone
		STATE_MACHINE_ENDED: begin
			MainStateMachine <= STATE_WAITING_FOR_COMMAND; // We're done...
		end			
	endcase
end

endmodule
