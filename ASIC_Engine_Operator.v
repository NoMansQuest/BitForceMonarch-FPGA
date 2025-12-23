`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 		 Butterfly Labs Inc.
// Engineer: 		 Nasser GHOSEIRI
// 
// Create Date:    03:16:45 03/06/2014 
// Design Name:     
// Module Name:    ASIC_Engine_Operator 
// Project Name:   Monarch
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

module ASIC_Engine_Operator
(
    input  SysClock,
    output SPI_MOSI,
    input  SPI_MISO,
    output SPI_CLOCK,
    output SPI_NCS,
	 input  [8:0]BusAddress,
	 output [31:0]BusExport,
	 input  OE,
	 input  CE,
	 input  [31:0]BusImport,
	 input  BusStrobe,
	 output OperatorBusy,
	 input [31:0]OPERATOR_COMMAND_REGISTER,
	 input [15:0]OPERATOR_REGISTER0_DEFAULT
);

// StaticParames
parameter bUseDebugFIFO = 1'b0;

// Our Ram-Select
wire RAM_Select = (BusAddress < 9'd495) ? 1'b1 : 1'b0;

// Our Register-0 Data for this tile
reg [15:0]REG0_DATA = 16'h00;

// Instantiate an SPI_Engine
wire [31:0]Tx_Data_For_SPI;
wire [15:0]Rx_Data_From_SPI;
wire SPI_Engine_Done;
wire SPI_Engine_Start_Switch;

SPI_Engine The_SPI_Engine 
(
    .clk_for_SPI(SysClock), 
    .SPI_CLOCK(SPI_CLOCK), 
    .SPI_MISO(SPI_MISO), 
    .SPI_MOSI(SPI_MOSI), 
    .SPI_NCS(SPI_NCS), 
    .Tx_Data(Tx_Data_For_SPI), 
    .Rx_Data(Rx_Data_From_SPI), 
    .EngineStart(SPI_Engine_Start_Switch), 
    .EngineDone(SPI_Engine_Done)
);


// Instantiate a memory block
wire [31:0]BusExport_Buffer_FromMemory;
wire  Memory_WriteEnable_Switched;
wire [8:0]Memory_Address_Switched;
wire  [31:0]Memory_WriteData_Switched;
wire [31:0]Memory_ReadData;

OPERATOR_RAM_16K Operator_Memory (
  .clka(BusStrobe),    
  .wea(CE & ~OE), 
  .addra(BusAddress),  
  .dina(BusImport),    
  .douta(BusExport_Buffer_FromMemory), 
  .clkb(SysClock),      
  .web(Memory_WriteEnable_Switched), 
  .addrb(Memory_Address_Switched),   
  .dinb(Memory_WriteData_Switched),  
  .doutb(Memory_ReadData)  
);


// Operator Command Register 
// Address: 0
reg  IsProcessorRunning = 1'b0;
wire [31:0]OPERATOR_STATUS_REGISTER;
reg  [31:0]OPERATOR_JOB_STATUS = 32'b0;

/*
 * Operator Command Register
 =================================================
 31                                              0
 +-----------------------------------------------+
 |				Reserved 	      | RUN OPERATOR |
 +-----------------------------------------------+
 
 
 * Operator Status Register
 =================================================
 31						 16 					 0
 +-----------------------------------------------+
 |				Reserved   		 |	  RUNNING	 |
 +-----------------------------------------------+


 * Operator Job Status
 =================================================
 31						 16	 					 0
 +-----------------------------------------------+
 |	 JobsInProcess-16Bit ||	JobDoneStatus-16Bit	 |
 +-----------------------------------------------+
 
*/

// Ok, Here we face the giant StateMachine (or should I say, processor in a way...)
reg [2:0]ActualChipToWorkOn = 3'b000; // Must be incremented in Run-Authorization-Check
reg [31:0]ActualAssumedState = 32'b0; // Bit0 = Hashing Job1, Bit1 = HashingJob2, Bit2 = Job1Done, Bit3 = Job2Done
reg [4:0]STATE_MACHINE_STATE = 5'b00000;

// General
reg [7:0]Loop_Variable = 8'b000000; // Used as a loop variable
reg [3:0]Loop_Variable2 = 4'b0; 
reg [3:0]Loop_Variable3 = 4'b0; 
reg [3:0]Loop_Variable4 = 4'b0; 
reg [3:0]Loop_Variable5 = 4'b0; 
reg [7:0]Loop_Variable6 = 8'b0; 
reg [3:0]Loop_Variable7 = 4'b0;
reg [7:0]Loop_Variable8 = 8'b0;
reg [3:0]Loop_Variable9 = 4'b0;
reg [3:0]Loop_Variable10 = 4'b0;

// Debug Variables
// reg [31:0]OPERATOR_DEBUG_VALUE = 32'b0;

// Continue...
reg [15:0]ActualEngineMap = 15'h0000; // Loaded with actual engine map
reg [15:0]TempEngineMap = 15'h0000;
reg SignalJobCompletion = 1'b0; // set by Read-Complete. Reset by CheckJobAvailability

reg [4:0]TotalValidEngines = 5'b0; // Used in LOAD_ENGINE_MAP, IS_TILE_BUSY_CHECK and SCAN_ENGINE_BUSY
wire [4:0]TotalEnginesBusy; 

parameter MACHINE_STATE_STARTING 						= 5'b00000;
parameter MACHINE_STATE_CHECK_RUN_AUTHORIZATION 	= 5'b00001;
parameter MACHINE_STATE_LOAD_ENGINE_MAP 				= 5'b00010;
parameter MACHINE_STATE_CHECK_ENGINE_ASSUMED_STATE = 5'b00101;
parameter MACHINE_STATE_SCAN_ENGINE_STATUS 			= 5'b00110;
parameter MACHINE_STATE_IS_TILE_BUSY_CHECK 			= 5'b00111;
parameter MACHINE_STATE_GET_NONCE_FROM_TILE 			= 5'b01000;
parameter MACHINE_STATE_ISSUE_READ_COMPLETE 			= 5'b01001;
parameter MACHINE_STATE_CHECK_JOB1_AVAILABLE 		= 5'b01010;
parameter MACHINE_STATE_CHECK_JOB2_AVAILABLE 		= 5'b01011;
parameter MACHINE_STATE_LOAD_JOB1_TO_TILE				= 5'b01100;
parameter MACHINE_STATE_LOAD_JOB2_TO_TILE				= 5'b01101;
parameter MACHINE_STATE_UPDATE_ASSUMED_STATE 		= 5'b01110;
parameter MACHINE_STATE_ISSUE_WRITE_COMPLETE 		= 5'b01111;
parameter MACHINE_STATE_LOAD_JOBS_STATUS				= 5'b10000;
parameter MACHINE_STATE_SAVE_JOBS_STATUS				= 5'b10001;
parameter MACHINE_STATE_LOAD_REG0						= 5'b10010;

// The numbers below are relative to BASE
wire [8:0]MEMORY_ADDRESS_ENGINE_HEALTH_MAP   = {ActualChipToWorkOn, 6'd0};
wire [8:0]MEMORY_ADDRESS_TILE_ASSUMED_STATE  = {ActualChipToWorkOn, 6'd1};
wire [8:0]MEMORY_ADDRESS_JOB1RES_NONCE_COUNT = {ActualChipToWorkOn, 6'd25};
wire [8:0]MEMORY_ADDRESS_JOB1RES_NONCES		= {ActualChipToWorkOn, 6'd26};
wire [8:0]MEMORY_ADDRESS_JOB2RES_NONCE_COUNT = {ActualChipToWorkOn, 6'd34};
wire [8:0]MEMORY_ADDRESS_JOB2RES_NONCES		= {ActualChipToWorkOn, 6'd35};
wire [8:0]MEMORY_ADDRESS_JOB1_STATUS			= {ActualChipToWorkOn, 6'd43};
wire [8:0]MEMORY_ADDRESS_JOB2_STATUS			= {ActualChipToWorkOn, 6'd44};
wire [8:0]MEMORY_ADDRESS_REG0_DATA				= {ActualChipToWorkOn, 6'd45};

wire [31:0]Bus_Export_Value = (RAM_Select) ? (BusExport_Buffer_FromMemory) :
                              (BusAddress == 9'd495) ? OPERATOR_STATUS_REGISTER :
										OPERATOR_COMMAND_REGISTER;
																				
assign BusExport = ((CE) & (OE)) ? Bus_Export_Value : 32'bZ;


///////////////////////////////////////////////
// Modules to instantiate
//////////////////////////////////////////////


// Status Checker Module
wire [31:0]SPI_TX_StatusChecker;
wire StatusCheckerModule_Done;
wire SPI_START_StatusChecker;
wire [31:0]StatusChecker_DebugExport;

uEngine_Engine_Status_Checker EngineStatusCheckerModule (
    .SysClock(SysClock), 
	 .ModuleStart((STATE_MACHINE_STATE == MACHINE_STATE_SCAN_ENGINE_STATUS) ? 1'b1 : 1'b0),
    .ModuleDone(StatusCheckerModule_Done), 
    .SPI_TX(SPI_TX_StatusChecker), 
    .SPI_RX(Rx_Data_From_SPI), 
    .SPI_START(SPI_START_StatusChecker), 
    .SPI_DONE(SPI_Engine_Done), 
    .EngineMap(ActualEngineMap), 
    .ActualChipIndex(ActualChipToWorkOn), 
    .TotalEnginesBusy(TotalEnginesBusy),
	 .DebugExport(StatusChecker_DebugExport)
    );


// Job-Issuance Module
wire SPI_START_JobIssuance;
wire [31:0]SPI_TX_JobIssuance;

wire JobIssuanceModule_Done;
wire Memory_WriteEnable_JobIssuance;
wire [8:0]Memory_Address_JobIssuance;
wire [15:0]JobIssuance_DebugExport;

uEngine_Job_Issuance JobIssuanceModule (
    .SysClock(SysClock), 
    .ModuleDone(JobIssuanceModule_Done), 
    .ModuleStart(((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) || (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE)) ? 1'b1 : 1'b0), 
    .SPI_TX(SPI_TX_JobIssuance), 
    .SPI_START(SPI_START_JobIssuance), 
    .SPI_DONE(SPI_Engine_Done), 
    .EngineMap(ActualEngineMap), 
    .ActualChipIndex(ActualChipToWorkOn), 
    .Memory_ReadData(Memory_ReadData), 
    .Memory_Address(Memory_Address_JobIssuance), 
	 .Memory_WriteEnable(Memory_WriteEnable_JobIssuance),
    .JobIndexToLoad((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) ? 1'b0 : 1'b1),
	 .DebugExport(JobIssuance_DebugExport)
    );
	 

// Nonce-Gathering Module
wire [31:0]Memory_WriteData_NonceGathering;
wire [8:0]Memory_Address_NonceGathering;
wire Memory_WriteEnable_NonceGathering;
wire NonceGatheringModule_Done;
wire [31:0]SPI_TX_NonceGathering;
wire SPI_START_NonceGathering;

uEngine_Nonce_Gathering NonceGathering_Module (
    .SysClock(SysClock), 
	 .ModuleStart((STATE_MACHINE_STATE == MACHINE_STATE_GET_NONCE_FROM_TILE) ? 1'b1 : 1'b0),
    .ModuleDone(NonceGatheringModule_Done), 
    .SPI_TX(SPI_TX_NonceGathering), 
    .SPI_RX(Rx_Data_From_SPI), 
    .SPI_START(SPI_START_NonceGathering), 
    .SPI_DONE(SPI_Engine_Done), 
    .EngineMap(ActualEngineMap), 
    .ActualChipIndex(ActualChipToWorkOn), 
    .Memory_ReadData(Memory_ReadData), 
    .Memory_WriteData(Memory_WriteData_NonceGathering), 
    .Memory_Address(Memory_Address_NonceGathering), 
    .Memory_WriteEnable(Memory_WriteEnable_NonceGathering), 
    .Memory_Address_To_Start_Storing((ActualAssumedState[0] == 1) ? MEMORY_ADDRESS_JOB1RES_NONCES : MEMORY_ADDRESS_JOB2RES_NONCES)
    );


// ReadComplete Module
wire [31:0]SPI_TX_ReadComplete;
wire SPI_START_ReadComplete;
wire ReadCompleteModule_Done;

uEngine_Read_Complete ReadComplete_Module (
    .SysClock(SysClock), 
    .ModuleDone(ReadCompleteModule_Done), 
    .ModuleStart((STATE_MACHINE_STATE == MACHINE_STATE_ISSUE_READ_COMPLETE) ? 1'b1 : 1'b0), 
    .SPI_TX(SPI_TX_ReadComplete), 
    .SPI_START(SPI_START_ReadComplete), 
    .SPI_DONE(SPI_Engine_Done), 
    .EngineMap(ActualEngineMap), 
    .ActualChipIndex(ActualChipToWorkOn), 
    .Register0Default(REG0_DATA)
    );


// WriteComplete Module
wire [31:0]SPI_TX_WriteComplete;
wire SPI_START_WriteComplete;
wire WriteCompleteModule_Done;

uEngine_Write_Complete WriteComplete_Module (
    .SysClock(SysClock), 
    .ModuleDone(WriteCompleteModule_Done), 
    .ModuleStart((STATE_MACHINE_STATE == MACHINE_STATE_ISSUE_WRITE_COMPLETE) ? 1'b1 : 1'b0), 
    .SPI_TX(SPI_TX_WriteComplete), 
    .SPI_START(SPI_START_WriteComplete), 
    .SPI_DONE(SPI_Engine_Done), 
    .EngineMap(ActualEngineMap), 
    .ActualChipIndex(ActualChipToWorkOn), 
    .Register0Default(REG0_DATA)
    );


// Switching Modules

assign Tx_Data_For_SPI = (STATE_MACHINE_STATE == MACHINE_STATE_ISSUE_WRITE_COMPLETE) ? SPI_TX_WriteComplete :
								  (STATE_MACHINE_STATE == MACHINE_STATE_ISSUE_READ_COMPLETE) ? SPI_TX_ReadComplete :
								  (STATE_MACHINE_STATE == MACHINE_STATE_GET_NONCE_FROM_TILE) ? SPI_TX_NonceGathering : 
								  ((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) || (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE)) ? SPI_TX_JobIssuance :
								  (STATE_MACHINE_STATE == MACHINE_STATE_SCAN_ENGINE_STATUS) ? SPI_TX_StatusChecker : 32'b0;
								  
assign SPI_Engine_Start_Switch = (STATE_MACHINE_STATE == MACHINE_STATE_ISSUE_WRITE_COMPLETE) ? SPI_START_WriteComplete :
								 (STATE_MACHINE_STATE == MACHINE_STATE_ISSUE_READ_COMPLETE) ? SPI_START_ReadComplete :
							     (STATE_MACHINE_STATE == MACHINE_STATE_GET_NONCE_FROM_TILE) ? SPI_START_NonceGathering : 
								 ((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) || (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE)) ? SPI_START_JobIssuance :
								 (STATE_MACHINE_STATE == MACHINE_STATE_SCAN_ENGINE_STATUS) ? SPI_START_StatusChecker : 1'b0;			

reg Memory_WriteEnable_Master = 1'b0;
reg [31:0]Memory_WriteData_Master = 32'b0;
reg [8:0]Memory_Address_Master = 9'b0;

assign Memory_WriteEnable_Switched = (STATE_MACHINE_STATE == MACHINE_STATE_GET_NONCE_FROM_TILE) ? Memory_WriteEnable_NonceGathering  :
												 ((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) || (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE)) ? 1'b0 :
												 Memory_WriteEnable_Master;

assign Memory_WriteData_Switched = (STATE_MACHINE_STATE == MACHINE_STATE_GET_NONCE_FROM_TILE) ? Memory_WriteData_NonceGathering :
											  ((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) || (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE)) ? 32'b0 :
											  Memory_WriteData_Master;

assign Memory_Address_Switched = (STATE_MACHINE_STATE == MACHINE_STATE_GET_NONCE_FROM_TILE) ? Memory_Address_NonceGathering :
											((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) || (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE)) ? Memory_Address_JobIssuance :
											Memory_Address_Master;

// Assignment to our operator status
assign OPERATOR_STATUS_REGISTER = {31'b0, IsProcessorRunning};
assign OperatorBusy = IsProcessorRunning;


// Actual Assumed State Monitor
wire bResetAssumedState = (STATE_MACHINE_STATE == MACHINE_STATE_STARTING) ? 1'b1 : 1'b0;
wire bLoadAssumedState = (STATE_MACHINE_STATE == MACHINE_STATE_CHECK_ENGINE_ASSUMED_STATE) ? 1'b1 : 1'b0;;
wire bClearAssumedState = ((STATE_MACHINE_STATE == MACHINE_STATE_CHECK_JOB1_AVAILABLE) || (STATE_MACHINE_STATE == MACHINE_STATE_CHECK_JOB2_AVAILABLE)) ? 1'b1 : 1'b0;
wire bSetAssumedState = ((STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) || (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE)) ? 1'b1 : 1'b0;

always @(posedge SysClock)
begin
	if (bResetAssumedState)
	begin
		ActualAssumedState <= 32'b0;		
	end
	else if (bLoadAssumedState)
	begin
		// Load state from Memory
		ActualAssumedState <= (Memory_ReadData[31:0]);	
	end
	else if (bClearAssumedState)
	begin
		ActualAssumedState <= 32'b0;	
	end
	else if (bSetAssumedState)
	begin
		ActualAssumedState[0] <= (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB1_TO_TILE) ? 1'b1 : 1'b0;
		ActualAssumedState[1] <= (STATE_MACHINE_STATE == MACHINE_STATE_LOAD_JOB2_TO_TILE) ? 1'b1 : 1'b0;	
	end
	else
	begin
		ActualAssumedState <= ActualAssumedState;
	end
end

// JOBs status
reg Job1Valid = 1'b0;
reg Job2Valid = 1'b0;

wire [1:0]AreJobsValidActualTile = {Job2Valid, Job1Valid};

// The Main Giant State Machine
always @(posedge SysClock)
begin

	// What's the state of the machine
	case (STATE_MACHINE_STATE)
		
		// Here, we're supposed to intialize
		MACHINE_STATE_STARTING:	begin
			Loop_Variable  <= 8'b0; // Initialize loop variable
			Loop_Variable2 <= 4'b0; // Initialize loop2 variable
			Job2Valid <= 1'b0;
			Job1Valid <= 1'b0;
			Memory_Address_Master <= 9'b0; // Reset Variable
			STATE_MACHINE_STATE <= MACHINE_STATE_CHECK_RUN_AUTHORIZATION;
			// OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01;
		end
				
		
		// Are we authorize to run? ALSO, increment CHIP index
		MACHINE_STATE_CHECK_RUN_AUTHORIZATION: begin
			// Increment Tile Index
			ActualChipToWorkOn <= ActualChipToWorkOn + 3'b001;
			
			// Should we 
			STATE_MACHINE_STATE <= (OPERATOR_COMMAND_REGISTER[0] == 1'b1) ? MACHINE_STATE_LOAD_ENGINE_MAP : MACHINE_STATE_STARTING;		
			
			// Also set the Memory address to where we need to load the Engine-Maps
			Memory_Address_Master <= MEMORY_ADDRESS_ENGINE_HEALTH_MAP;
			
			// Are we running?
			IsProcessorRunning <= OPERATOR_COMMAND_REGISTER[0];
			// OPERATOR_DEBUG_VALUE <= 32'b010;
		end				
		
		
		// Load engine map. This tells us how many engines are good
		// Structure of EngineMap is as following
		// 
		// 31			   | 19			  16 | 15								 0
		// +---------------------------------------------------------+
		// |	Reserved |	Engine Count  |	Engine Validity Map		 |				
		// +---------------------------------------------------------+
		MACHINE_STATE_LOAD_ENGINE_MAP: begin
			if (Loop_Variable == 8'b0)
			begin
				 Loop_Variable <= 8'b01;
				 
				 // Also set the Memory address to where we need to load the Engine-Maps
				 Memory_Address_Master <= MEMORY_ADDRESS_ENGINE_HEALTH_MAP;

				 // This is for one cycle delay to make sure memory content is loaded
				 // OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b0100;
			end
			else if (Loop_Variable == 8'b01)
			begin
				 Loop_Variable <= 8'b10;
				 // This is for one cycle delay to make sure memory content is loaded
				 // OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01000;
			end
			else
			begin
				// Also Load ActualEngineMap
				ActualEngineMap <= Memory_ReadData[15:0];
				TotalValidEngines <= Memory_ReadData[20:16];
				
				// Engine count is available from bit 16 to 19 of MemoryReadData
				// We don't proceed if total engine count is only 2
				if (Memory_ReadData[20:16] < 2)
				begin
					STATE_MACHINE_STATE <= MACHINE_STATE_STARTING;
					//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b010000;
				end
				else
				begin
					STATE_MACHINE_STATE <= MACHINE_STATE_LOAD_REG0;
					//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b0100000;
				end
				
				// Set memory address to load the assumed state
				Memory_Address_Master <= MACHINE_STATE_LOAD_ENGINE_MAP;
				Loop_Variable <= 8'b0;						
			end
		end
		
		// Here we load Register-0 Data 
		MACHINE_STATE_LOAD_REG0: begin
			if (Loop_Variable == 8'd0)
			begin
				Memory_Address_Master <= MEMORY_ADDRESS_REG0_DATA;
				Loop_Variable <= 8'd1;				
			end
			else if (Loop_Variable == 8'd1)
			begin
				Loop_Variable <= 8'd2;
			end
			else
			begin
				REG0_DATA <= Memory_ReadData[15:0];
				Loop_Variable <= 8'd0;
				STATE_MACHINE_STATE <= MACHINE_STATE_LOAD_JOBS_STATUS;
			end		
		end
		
		// Here we load our Job-Status
		MACHINE_STATE_LOAD_JOBS_STATUS: begin
			if (Loop_Variable == 8'b0)
			begin
				Loop_Variable <= 8'b01;
				Memory_Address_Master <= MEMORY_ADDRESS_JOB1_STATUS;
			end
			else if (Loop_Variable == 8'b01)
			begin
				Loop_Variable <= 8'b10;
			end
			else if (Loop_Variable == 8'b10)
			begin
				Job1Valid <= (Memory_ReadData[3:0] == 4'hA) ? 1'b1 : 1'b0;
				Memory_Address_Master <= MEMORY_ADDRESS_JOB2_STATUS;
				Loop_Variable <= 8'b11;						
			end
			else if (Loop_Variable == 8'b11)
			begin
				Loop_Variable <= 8'b100;						
			end			
			else
			begin
				Job2Valid <= (Memory_ReadData[3:0] == 4'hA) ? 1'b1 : 1'b0;
				Loop_Variable <= 8'b00;
				STATE_MACHINE_STATE <= MACHINE_STATE_CHECK_ENGINE_ASSUMED_STATE;
				Memory_Address_Master <= MEMORY_ADDRESS_TILE_ASSUMED_STATE;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01000000;
			end			
			
		end
		
		// Here, we check the assume state, and make a decision based. 
		// If it's not working on either job, then we need to check for job availability and issue it to the tile (if one exists)
		// If it's working on something, we need to see if it has finished, gather the nonces and proceed with the job issuance
		MACHINE_STATE_CHECK_ENGINE_ASSUMED_STATE: begin
			if (Loop_Variable == 8'b0)
			begin
				Loop_Variable <= 8'b01;
				// This is a delay to make sure AssumedState is loaded correctly
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b010000000;
			end
			else
			begin
				// Ok, now if we are working on something, then we need to scan engines register0 and take it from there
				// Otherwise, we need to send a job to the tile
				if ((Memory_ReadData[0] | Memory_ReadData[1]) == 1'b1)
				begin
					STATE_MACHINE_STATE <= MACHINE_STATE_SCAN_ENGINE_STATUS; 
					//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b0100000000;
				end
				else
				begin
					STATE_MACHINE_STATE <= MACHINE_STATE_CHECK_JOB1_AVAILABLE;
					//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01000000000;
				end			
			end			
		end
		
		
		// Here, we need to scan Register-0 of engines 1 to 16, and see how many are running, how many finished
		MACHINE_STATE_SCAN_ENGINE_STATUS: begin
			// Loop Variable2 is used as our monitor. Loop-Variable is used are Engine Address
			if (StatusCheckerModule_Done)
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_IS_TILE_BUSY_CHECK;			
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b010000000000;
			end
			else
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_SCAN_ENGINE_STATUS;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b0100000000000;
			end
		end 
		
		
		// Now, we know how many engines have finished or running, make a decision based on it
		MACHINE_STATE_IS_TILE_BUSY_CHECK: begin
			if (TotalEnginesBusy > 2) // It means we aren't done yet
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_UPDATE_ASSUMED_STATE;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01000000000000;
			end
			else
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_GET_NONCE_FROM_TILE;			
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b010000000000000;
			end
		end
		
		
		// Here we have to scan all fifos, see if any nonce was detected!
		MACHINE_STATE_GET_NONCE_FROM_TILE: begin		
			if (NonceGatheringModule_Done)
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_ISSUE_READ_COMPLETE;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b0100000000000000;
			end
			else
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_GET_NONCE_FROM_TILE;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01000000000000000;
			end
		end	
		
	
		// We issue the read-complete to all engines!
		MACHINE_STATE_ISSUE_READ_COMPLETE: begin
			if (ReadCompleteModule_Done)
			begin
				Loop_Variable <= 8'b0;
				STATE_MACHINE_STATE <= MACHINE_STATE_SAVE_JOBS_STATUS; // This way, MCU will be informed that the job was done...
				//STATE_MACHINE_STATE <= (ActualAssumedState[0] ? MACHINE_STATE_CHECK_JOB2_AVAILABLE : MACHINE_STATE_CHECK_JOB1_AVAILABLE); // If we had processed JOB1, Check JOB2 first this time
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b010000000000000000;
			end
			else
			begin
				STATE_MACHINE_STATE <= STATE_MACHINE_STATE;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b0100000000000000000;
			end
		end
		
		// Save Job Status in Memory
		MACHINE_STATE_SAVE_JOBS_STATUS: begin
			if (Loop_Variable == 8'b0)
			begin
				Memory_Address_Master <= (ActualAssumedState[0] ? MEMORY_ADDRESS_JOB1_STATUS : MEMORY_ADDRESS_JOB2_STATUS);
				Memory_WriteData_Master <= 32'h0000000B; // B means DONE
				Memory_WriteEnable_Master <= 1'b1;
				Loop_Variable <= 8'b01;
			end
			else if (Loop_Variable == 8'b01)
			begin
				// JOB status was saved. We're done
				Loop_Variable <= 8'b0;
				Memory_WriteEnable_Master <= 1'b0;
				
				// We move to next state
				STATE_MACHINE_STATE <= (ActualAssumedState[0] ? MACHINE_STATE_CHECK_JOB2_AVAILABLE : MACHINE_STATE_CHECK_JOB1_AVAILABLE); // If we had processed JOB1, Check JOB2 first this time
			end		
			//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01000000000000000000;
		end
		
		// Is Job1 Available? If so, we can issue it. If not, go to job-2 availability check
		MACHINE_STATE_CHECK_JOB1_AVAILABLE: begin
			// Here, we check to see if Bit-0 of AreJobsValidActualTile!
			if (AreJobsValidActualTile[0] == 0)
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_CHECK_JOB2_AVAILABLE;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b010000000000000000000;
			end
			else
			begin
				// We have a job. We need to send it to the chip!
				STATE_MACHINE_STATE <= MACHINE_STATE_LOAD_JOB1_TO_TILE;
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b0100000000000000000000;
			end
			
			// Either way, we do reset SignalJobCompletion
			Loop_Variable2 <= 4'b0000;
		end		
		
		
		// Is Job2 Available? If not, we simply have to abort, as there is no job to issue
		MACHINE_STATE_CHECK_JOB2_AVAILABLE: begin
			// Here, we check to see if Bit-1 of AreJobsValidActualTile
			if (AreJobsValidActualTile[1] == 0)
			begin
				// Abort... There is nothing to do!
				Loop_Variable2 <= 4'b0000;
				STATE_MACHINE_STATE <= MACHINE_STATE_UPDATE_ASSUMED_STATE; // We need to update this state value anyway
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b01000000000000000000000;
			end
			else
			begin
				// We have a job. We need to send it to the chip!
				STATE_MACHINE_STATE <= MACHINE_STATE_LOAD_JOB2_TO_TILE;				
				//OPERATOR_DEBUG_VALUE <= OPERATOR_DEBUG_VALUE | 32'b010000000000000000000000;
			end	

			// Either way, we do reset SignalJobCompletion
			Loop_Variable2 <= 4'b0000;
		end	
	
					
		// Load Job-1 (or Job-2) data to the Tile
		// This is a loop, that reads data one by one, and sends it to the chip (provided the engine does exist)
		MACHINE_STATE_LOAD_JOB1_TO_TILE, MACHINE_STATE_LOAD_JOB2_TO_TILE: begin
			if (JobIssuanceModule_Done)
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_ISSUE_WRITE_COMPLETE;
				//OPERATOR_DEBUG_VALUE <= 32'b0100000000000000000000;
			end
			else
			begin
				STATE_MACHINE_STATE <= STATE_MACHINE_STATE;
				//OPERATOR_DEBUG_VALUE <= (32'b01000000000000000000000) | JobIssuance_DebugExport;
			end
		end		
		
		// We need to update that register in RAM 
		MACHINE_STATE_UPDATE_ASSUMED_STATE: begin
			if (Loop_Variable2 == 4'b0000)
			begin 
				Memory_WriteData_Master <= ActualAssumedState[31:0] ^ 32'h80000000; // Flip MSB to indicate activity
				Memory_Address_Master <= MEMORY_ADDRESS_TILE_ASSUMED_STATE;
				Memory_WriteEnable_Master <= 1'b1;
				Loop_Variable2 <= 4'b0001; // Go to the next stage
				//OPERATOR_DEBUG_VALUE <= 32'b010000000000000000000000;
			end
			else
			begin
				Memory_WriteEnable_Master <= 1'b0;				
				STATE_MACHINE_STATE <= MACHINE_STATE_STARTING;
				//OPERATOR_DEBUG_VALUE <= 32'b0100000000000000000000000;
			end
		end	
		
		
		// Here we RESET the engines and issue WRITE_COMPLETE
		MACHINE_STATE_ISSUE_WRITE_COMPLETE: begin
			// Loop Variable2 is used as our monitor. Loop-Variable is used are Engine Address
			if (WriteCompleteModule_Done)
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_UPDATE_ASSUMED_STATE;
				Loop_Variable2 <= 4'b0000;
				//OPERATOR_DEBUG_VALUE <= 32'b01000000000000000000000000;
			end
			else
			begin
				STATE_MACHINE_STATE <= MACHINE_STATE_ISSUE_WRITE_COMPLETE;
				//OPERATOR_DEBUG_VALUE <= 32'b010000000000000000000000000;
			end
		end
		
		
		default: begin
			STATE_MACHINE_STATE <= MACHINE_STATE_STARTING;
			//OPERATOR_DEBUG_VALUE <= 32'b0100000000000000000000000000;
		end
						
	endcase
end

endmodule
