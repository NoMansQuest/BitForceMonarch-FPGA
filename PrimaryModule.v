`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    00:28:59 10/24/2013 
// Design Name: 
// Module Name:    PrimaryModule 
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
module PrimaryModule
	(
		// On-board clock
		clk_main,
		
		// MCU
		MCU_BUS,
		MCU_STROBE,
		MCU_GENERAL_RESET,
		MCU_OE,
		MCU_ADR,
		MCU_SPI_MISO,
		MCU_SPI_MOSI,
		MCU_SPI_CLK,
		MCU_SPI_NCS,
		
		// VRM & FPGA
		VRM_VID,
		LED_FPGA,
		
		// FAN Control
		FAN_CONTROL,
		FAN_CONTROL_P,
		
		// PCI Express
		pcie_rx_p,
		pcie_rx_n,
		pcie_tx_p,
		pcie_tx_n,
		pcie_refclk_p,
		pcie_refclk_n,
		pcie_PERSTn,
		
		// ASICs
		asic_spi_miso,
		asic_spi_mosi,
		asic_spi_clock,
		asic_spi_cs,
		asic_PORB1,
		asic_PORB2,
		
		// VRM Control Clocks for ADP1851 Backup Plan
		VRM_clock
	);
	
	//////////////////////////////////////////////////////////////////////
	// Board main oscillator clock
	input  clk_main;
	
	// Accelerate main_clock to 150MHz, from 50MHz. This gives us better resolution
	reg clk_16MHz = 1'b0;
	wire  clk_32MHz, DCM_TMDS_CLKFX;
	DCM_SP #(.CLKFX_MULTIPLY(2), .CLKFX_DIVIDE(3), .CLKOUT_PHASE_SHIFT("FIXED")) DCM_TMDS_inst(.CLKIN(clk_main), .CLKFX(DCM_TMDS_CLKFX), .RST(1'b0), .PSEN(0));
	BUFG BUFG_TMDSp(.I(DCM_TMDS_CLKFX), .O(clk_32MHz));  // 150 MHz
		
	// Our 25MHz clock
	//reg   [2:0]clk_20MHz_Counter = 3'b0;
	//always @(posedge clk_main) clk_20MHz_Counter <= (clk_20MHz_Counter == 3'd5) ? 3'd0 : clk_20MHz_Counter + 3'b001;
	always @(posedge clk_32MHz) clk_16MHz <= ~clk_16MHz;
	wire clk_SPI_System = clk_16MHz;
	//always @(posedge clk_main) clk_SPI_System <= ~clk_SPI_System;
	
	// MCU 
	inout  [31:0] MCU_BUS;
	input  MCU_STROBE;
	input  MCU_OE;
	input  MCU_GENERAL_RESET;
	input  MCU_ADR;
	output MCU_SPI_MISO;
	input  MCU_SPI_MOSI;
	input  MCU_SPI_CLK;
	input  MCU_SPI_NCS;
	
	// Outputs as VRM clocks
	output [5:0]VRM_clock;
	
	// ASICs
	input  [15:0]asic_spi_miso;
	output [15:0]asic_spi_mosi;
	output [15:0]asic_spi_clock;
	output [15:0]asic_spi_cs;
	output reg asic_PORB1 = 1'b0;
	output reg asic_PORB2 = 1'b0;
	

	
	// FAN 
	output reg [3:0]FAN_CONTROL = 4'b0000;
	output reg [3:0]FAN_CONTROL_P = 4'b1111;
	//output [3:0]FAN_CONTROL_P;
	// assign FAN_CONTROL_P	= 4'bZZZZ;
	
	// VRM & FPGA
	output [7:0]VRM_VID;
	output LED_FPGA;	

	// PCI Express
	input  pcie_rx_p;
	input  pcie_rx_n;
	output pcie_tx_p;
	output pcie_tx_n;
	input  pcie_refclk_p;
	input  pcie_refclk_n;
	input  pcie_PERSTn;
	wire   pcie_PERST = ~pcie_PERST;
	//////////////////////////////////////////////////////////////////
		
	//////////////////////////////////////////////////////////////////
	// PCI Express handling sub-system
	//////////////////////////////////////////////////////////////////
	
	// PCI Express System
	wire   clk_sync_pci;	
	wire   pcie_link_active;
	wire   pcie_hot_reset;
	
	wire   [9:0]BAR0_mem_read_adrs;
	wire	 BAR0_mem_read_clock;
	wire   [31:0]BAR0_mem_read_data;
	wire   BAR0_mem_read_enable;
	
	wire   [9:0]BAR1_mem_write_adrs;
	wire	 BAR1_mem_write_clock;
	wire   [31:0]BAR1_mem_write_data;
	wire   BAR1_mem_write_enable;	
	
	wire   [31:0]BAR2_IncomingCommand;
	wire	 BAR2_IncomingCommandStrobe;
	wire	 [31:0]BAR2_IncomingCommand2;
	wire   BAR2_IncomingCommand2Strobe;
	
	wire   [31:0]BAR2_StatusRegister1;
	wire   [31:0]BAR2_StatusRegister2;
	wire   [31:0]BAR2_StatusRegister3;
	wire   [31:0]BAR2_StatusRegister4;
		
	// Instantiate the module
	wire pcie_intercepted_clock;
	IBUFDS IBUFDS_pci_express_clock (
		.O(pcie_intercepted_clock), // Buffer output
		.I(pcie_refclk_p), // Diff_p buffer input (connect directly to top-level port)
		.IB(pcie_refclk_n) // Diff_n buffer input (connect directly to top-level port)
	);	

		
	wire AnyTLPsReceivedEver;
	wire pcie_reset_completed;
	wire [2:0]MemoryRequestRefused;
	wire MemoryRequestCompletedSuccessfully;
	wire MemoryRequestInProgress;
	wire DebugConditionMet;
	
	PCIExpress_Handler Main_PCI_Express 
	(
		 .pcie_intercepted_clock(pcie_intercepted_clock),
		 .pcie_sync_clock(clk_sync_pci), 
		 .pcie_link_active(pcie_link_active), 
		 .pcie_PERSTn(pcie_PERSTn), 
		 .pcie_hot_reset(pcie_hot_reset), 
		 .pcie_reset_completed(pcie_reset_completed),
		 .pcie_tx_p(pcie_tx_p), 
		 .pcie_tx_n(pcie_tx_n), 
		 .pcie_rx_p(pcie_rx_p), 
		 .pcie_rx_n(pcie_rx_n), 
		 .BAR0_mem_read_adrs(BAR0_mem_read_adrs), 
		 .BAR0_mem_read_clock(BAR0_mem_read_clock), 
		 .BAR0_mem_read_data(BAR0_mem_read_data), 
		 .BAR0_mem_read_enable(BAR0_mem_read_enable), 
		 .BAR1_mem_write_adrs(BAR1_mem_write_adrs), 
		 .BAR1_mem_write_clock(BAR1_mem_write_clock), 
		 .BAR1_mem_write_data(BAR1_mem_write_data), 
		 .BAR1_mem_write_enable(BAR1_mem_write_enable), 
		 .BAR2_ADRS2_StatusRegister1(BAR2_StatusRegister1), 
		 .BAR2_ADRS2_StatusRegister1_ReadStrobe(BAR2_StatusRegister1_ReadStrobe), 
		 .BAR2_ADRS3_StatusRegister2(BAR2_StatusRegister2), 
		 .BAR2_ADRS3_StatusRegister2_ReadStrobe(), 
		 .BAR2_ADRS4_StatusRegister3(BAR2_StatusRegister3), 
		 .BAR2_ADRS4_StatusRegister3_ReadStrobe(), 
		 .BAR2_ADRS5_StatusRegister4(BAR2_StatusRegister4), 
		 .BAR2_ADRS5_StatusRegister4_ReadStrobe(), 
		 .BAR2_ADRS0_Command1RegisterStrobe(BAR2_IncomingCommandStrobe), 
		 .BAR2_ADRS0_Command1RegisterData(BAR2_IncomingCommand), 
		 .BAR2_ADRS1_Command2RegisterStrobe(BAR2_IncomingCommand2Strobe), 
		 .BAR2_ADRS1_Command2RegisterData(BAR2_IncomingCommand2),
		 .AnyTLPsReceivedEver(AnyTLPsReceivedEver),
		 .MemoryRequestRefused(MemoryRequestRefused),
		 .MemoryRequestCompletedSuccessfully(MemoryRequestCompletedSuccessfully),
		 .MemoryRequestInProgress(MemoryRequestInProgress),
		 .DebugConditionMet(DebugConditionMet)
   );
	

	///////////////////////////////////////////////////////////////////
	// Internal Registers and Variables
	///////////////////////////////////////////////////////////////////
	reg [18:0]REG_dispatch_address = 19'b0;

	reg [31:0]REG_SPI_switch = 32'b0;
	//reg [07:0]REG_VRM_VID = 8'b10011010; // Set to 0.65V by default, VR11 Code
	reg [07:0]REG_VRM_VID = 8'b00000000; // Set to 0, turning off the VRM or setting it to 0.6V by default 
	reg [31:0]REG_temperature_sensor = 32'b0;
	reg [31:0]REG_system_information = 32'b0;
	
	reg [31:0]REG_command_execution = 32'b0;
	reg [31:0]REG_command_status = 32'b0; 

	// DISABLED FOR DEBUG
	assign VRM_VID = REG_VRM_VID[7:0];
	//assign VRM_VID = 8'b0;
	
	
	///////////////////////////////////////////////////////////////////
	// MCU Control Region
	//////////////////////////////////////////////////////////////////
	parameter __ADRS_REG_BAR0_MEMORY			 = 0;
	parameter __ADRS_REG_BAR1_MEMORY			 = 1024;
	parameter __ADRS_REG_SPI_switch 		    = 2048;
	parameter __ADRS_REG_VRM_VID	  			 = 2060;
	parameter __ADRS_REG_ID			  			 = 2054;
	parameter __ADRS_REG_temperature_sensor = 2050;
	parameter __ADRS_REG_system_information = 2051;
	parameter __ADRS_REG_command_execution  = 2052;
	parameter __ADRS_REG_command_status 	 = 2053;
	parameter __ADRS_REG_FAN					 = 2055;
	parameter __ADRS_REG_PCIE_link_status 	 = 2056;
	parameter __ADRS_REG_SPI_availability	 = 2057;
	parameter __ADRS_REG_ASIC_PORB			 = 2058;
	
	wire [31:0]MCU_BUS_export;
	wire [31:0]MCU_BUS_import;
	wire [31:0]SPI_Availability_Wire; // Says if engines are actually operating on SPI's or not
	
	assign MCU_BUS = (MCU_OE) ? MCU_BUS_export : 32'bZ;
	assign MCU_BUS_import = (MCU_OE == 1'b0)? MCU_BUS : 32'b0;
	
	// Address capturing and incrementing	
	always @(negedge MCU_STROBE)
	begin
		if (MCU_ADR)
		begin
			if (~MCU_OE)
			begin
				REG_dispatch_address <= MCU_BUS_import[18:0];				
			end
			else
			begin
				REG_dispatch_address <= REG_dispatch_address;				
			end
		end
		else
		begin
			REG_dispatch_address <= REG_dispatch_address + 19'h0001;					
		end	
	end	

	// Read or Write request detection
	wire __MCU_WRITE_REQUEST = ~MCU_OE & ~MCU_ADR & MCU_STROBE;
	wire __MCU_READ_REQUEST  = MCU_OE  & ~MCU_ADR;
	
	
	assign MCU_REQUESTING_BAR_MEMORY_READ 			  = (REG_dispatch_address[18:10] == 9'b000000000);
	assign MCU_REQUESTING_TEMP_SENSOR_READ 		  = (REG_dispatch_address == __ADRS_REG_temperature_sensor);
	assign MCU_REQUESTING_SYSTEM_INFORMATION_READ  = (REG_dispatch_address == __ADRS_REG_system_information);
	assign MCU_REQUESTING_COMMAND_EXECUTION_READ   = (REG_dispatch_address == __ADRS_REG_command_execution);
	assign MCU_REQUESTING_COMMAND_STATUS_READ 	  = (REG_dispatch_address == __ADRS_REG_command_status);
	assign MCU_REQUESTING_SPI_SWITCH_READ			  = (REG_dispatch_address == __ADRS_REG_SPI_switch);
	assign MCU_REQUESTING_ID_READ			 			  = (REG_dispatch_address == __ADRS_REG_ID);
	assign MCU_REQUESTING_FAN_READ		 			  = (REG_dispatch_address == __ADRS_REG_FAN);
	assign MCU_REQUESTING_LINK_STATUS_READ			  = (REG_dispatch_address == __ADRS_REG_PCIE_link_status);
	assign MCU_REQUESTING_SPI_AVAILABILITY_READ	  = (REG_dispatch_address == __ADRS_REG_SPI_availability);
	assign MCU_REQUESTING_ASIC_PORB_READ			  = (REG_dispatch_address == __ADRS_REG_ASIC_PORB);	

	
	assign MCU_REQUESTING_BAR_MEMORY_WRITE			  = ((( REG_dispatch_address[18:10] == 9'b000000001)) ? 1'b1 : 1'b0) & ~MCU_OE & ~MCU_ADR;
	assign MCU_REQUESTING_TEMP_SENSOR_WRITE 		  = ((REG_dispatch_address == __ADRS_REG_temperature_sensor) ? 1'b1 : 1'b0) & ~MCU_OE & ~MCU_ADR;
	assign MCU_REQUESTING_SYSTEM_INFORMATION_WRITE = ((REG_dispatch_address == __ADRS_REG_system_information) ? 1'b1 : 1'b0) & ~MCU_OE & ~MCU_ADR;
	assign MCU_REQUESTING_COMMAND_EXECUTION_WRITE  = ((REG_dispatch_address == __ADRS_REG_command_execution) ? 1'b1 : 1'b0) & ~MCU_OE & ~MCU_ADR;
	assign MCU_REQUESTING_COMMAND_STATUS_WRITE 	  = ((REG_dispatch_address == __ADRS_REG_command_status) ? 1'b1 : 1'b0) & ~MCU_OE & ~MCU_ADR;
	assign MCU_REQUESTING_SPI_SWITCH_WRITE			  = ((REG_dispatch_address == __ADRS_REG_SPI_switch) ? 1'b1 : 1'b0) & ~MCU_OE & ~MCU_ADR;	
	assign MCU_REQUESTING_ASIC_PORB_WRITE			  = ((REG_dispatch_address == __ADRS_REG_ASIC_PORB) ? 1'b1 : 1'b0) & ~MCU_OE & ~MCU_ADR;	
	
	assign BAR0_mem_read_adrs = REG_dispatch_address;
	// assign BAR0_mem_read_clock = MCU_STROBE;
	assign BAR0_mem_read_clock = clk_main;
	assign BAR0_mem_read_enable = MCU_REQUESTING_BAR_MEMORY_READ;
	
	assign BAR1_mem_write_adrs = REG_dispatch_address;
	assign BAR1_mem_write_clock = MCU_STROBE;
	assign BAR1_mem_write_data = MCU_BUS_import;
	assign BAR1_mem_write_enable = MCU_REQUESTING_BAR_MEMORY_WRITE;

	wire[31:0]Extended_Export; // This goes beyond ordinary export (SPI Operator Engines)
	
														
	
		
	always @(posedge __MCU_WRITE_REQUEST)
	begin			
			if (REG_dispatch_address == __ADRS_REG_SPI_switch)	
				REG_SPI_switch <= MCU_BUS_import;
			else if (REG_dispatch_address == __ADRS_REG_VRM_VID) 
				REG_VRM_VID	<= MCU_BUS_import[7:0];
			else if (REG_dispatch_address == __ADRS_REG_temperature_sensor)
				REG_temperature_sensor <= MCU_BUS_import;
			else if (REG_dispatch_address == __ADRS_REG_system_information)
				REG_system_information <= MCU_BUS_import;
			else if (REG_dispatch_address == __ADRS_REG_command_status)
				REG_command_status <= MCU_BUS_import;
			else if (REG_dispatch_address == __ADRS_REG_FAN)
				FAN_CONTROL <= MCU_BUS_import[3:0];
			else if (REG_dispatch_address == __ADRS_REG_ASIC_PORB)
			begin
				asic_PORB1 <= MCU_BUS_import[0];
				asic_PORB2 <= MCU_BUS_import[1];
			end				
	end
	
	always @(posedge BAR2_IncomingCommandStrobe)
	begin
		REG_command_execution <= BAR2_IncomingCommand;
	end
	
	assign BAR2_StatusRegister1 =	REG_command_status;
	assign BAR2_StatusRegister2 = REG_system_information;
	assign BAR2_StatusRegister3 = REG_temperature_sensor;
	assign BAR2_StatusRegister4 = REG_command_execution;
	
		// Blink the primary LED
	reg [25:0]led_pulse_counter;	
	
	always @(posedge clk_SPI_System)
	begin
		led_pulse_counter <= led_pulse_counter + 26'h1;
	end
	
	////////////////////////////////////////////////////////////////////////////////////////////////////
	// Output VRM clocks (for 1853 backup plan, 1MHz output)
	// Assuming input frequency is 50MHz	
	////////////////////////////////////////////////////////////////////////////////////////////////////
	
	// Now divide the clock by 4 to get 200KHz on the output
	/*
	reg [1:0]clk_counter_div2;
	wire clk_150MHz_div2;
	always @(posedge clk_150MHz) clk_counter_div2 <= clk_counter_div2 + 2'b01;
	assign clk_150MHz_div2 = clk_counter_div2[0];
		
	reg [7:0]VRM_clock1_holder = 8'd0;
	reg [7:0]VRM_clock2_holder = 8'd32;
	reg [7:0]VRM_clock3_holder = 8'd64;
	reg [7:0]VRM_clock4_holder = 8'd96;
	reg [7:0]VRM_clock5_holder = 8'd128;
	reg [7:0]VRM_clock6_holder = 8'd160;	
	
	reg [2:0]iActualPhase = 3'b0;
	reg [7:0]iActualPhaseCounter = 8'b0;
	
	always @(posedge clk_150MHz_div2)
	begin
		VRM_clock1_holder <= (VRM_clock1_holder >= 8'd192) ? 8'd0 : (VRM_clock1_holder + 8'd1);
		VRM_clock2_holder <= (VRM_clock2_holder >= 8'd192) ? 8'd0 : (VRM_clock2_holder + 8'd1);
		VRM_clock3_holder <= (VRM_clock3_holder >= 8'd192) ? 8'd0 : (VRM_clock3_holder + 8'd1);
		VRM_clock4_holder <= (VRM_clock4_holder >= 8'd192) ? 8'd0 : (VRM_clock4_holder + 8'd1);
		VRM_clock5_holder <= (VRM_clock5_holder >= 8'd192) ? 8'd0 : (VRM_clock5_holder + 8'd1);
		VRM_clock6_holder <= (VRM_clock6_holder >= 8'd192) ? 8'd0 : (VRM_clock6_holder + 8'd1);
	end
	
	
	//assign VRM_clock[0] = ((VRM_clock1_holder > 8'd0) && (VRM_clock1_holder < 8'd31)) ? 1'b1 : 1'b0;
	//assign VRM_clock[1] = ((VRM_clock2_holder > 8'd0) && (VRM_clock2_holder < 8'd31)) ? 1'b1 : 1'b0;
	//assign VRM_clock[2] = ((VRM_clock3_holder > 8'd0) && (VRM_clock3_holder < 8'd31)) ? 1'b1 : 1'b0;
	//assign VRM_clock[3] = ((VRM_clock4_holder > 8'd0) && (VRM_clock4_holder < 8'd31)) ? 1'b1 : 1'b0;
	//assign VRM_clock[4] = ((VRM_clock5_holder > 8'd0) && (VRM_clock5_holder < 8'd31)) ? 1'b1 : 1'b0;
	//assign VRM_clock[5] = ((VRM_clock6_holder > 8'd0) && (VRM_clock6_holder < 8'd31)) ? 1'b1 : 1'b0;	
		
	assign VRM_clock[0] =  (VRM_clock1_holder < 8'd96) ? 1'b1 : 1'b0;
	assign VRM_clock[1] =  (VRM_clock2_holder < 8'd96) ? 1'b1 : 1'b0;
	assign VRM_clock[2] =  (VRM_clock3_holder < 8'd96) ? 1'b1 : 1'b0;
	assign VRM_clock[3] =  (VRM_clock4_holder < 8'd96) ? 1'b1 : 1'b0;
	assign VRM_clock[4] =  (VRM_clock5_holder < 8'd96) ? 1'b1 : 1'b0;
	assign VRM_clock[5] =  (VRM_clock6_holder < 8'd96) ? 1'b1 : 1'b0;		
	*/
	
	assign VRM_clock = 6'bZZZZZZ;
	
	/////////////////////////////////////////////////////////////////////////////////////////
	// Connect MCU signals to desired output bus
	/////////////////////////////////////////////////////////////////////////////////////////
	wire Engine_Execute_Strobe;
	wire [2:0]Engine_Command_To_Execute;
	
	// Note: REG_DISPATCH[16:12] tells us which engine we're trying to access
	// 16:12 == 5'b00001 means Engine-1
	// 16:12 == 5'b10000 means Engine-16
	
	// OFFSET MAP:
	// Offset 0     : Processor Engine 0 Default
	// Offset 1 to 4: Processor Response Data (128 Bit)
	// Offset 5		 : Command To Execute
	// Offset 6		 : Strobe Address (it's subsequent to Command-To-Execute, so only one additional strobe will automatically strobe the engine)
	
	
	wire [31:0]Operators_Bus_Export;
	reg  bDebugConditionMet = 1'b0;
	
	genvar i;
	generate
		for (i = 0; i < 16; i = i + 1) begin : MLOOP
		
			// Wire SPI intermediatery wires
			wire engine_SPI_MOSI;
			wire engine_SPI_MISO;
			wire engine_SPI_CLOCK;
			wire engine_SPI_NCS;
			wire Operator_Busy;
			wire [15:0]CycleCounter;
			
			// Is actual address point at us?
			wire IS_ADDRESS_POINTING_AT_US = (REG_dispatch_address[18:14] == (i+1)) ? 1'b1 : 1'b0;
			wire [11:0]ACTUAL_OFFSET = REG_dispatch_address[11:0];
			
			// Is it Command Execution Strobe?
			wire Engine_Strobe = (~MCU_ADR) & MCU_STROBE;
			
			// Manage Command-Register, etc
			reg [31:0]OPERATOR_COMMAND_REGISTER = 32'b0;
			reg [15:0]OPERATOR_REGISTER0_DEFAULT = 16'b0;
			reg [31:0]OPERATOR_JOB_VALIDATION_REGISTER = 32'b0;
			
			// Manage Command-Register, etc
			always @(posedge Engine_Strobe)
			begin
				OPERATOR_COMMAND_REGISTER  <= ((IS_ADDRESS_POINTING_AT_US == 1'b1) && (MCU_OE == 1'b0) && (ACTUAL_OFFSET[8:0] == 9'd493)) ? MCU_BUS_import : OPERATOR_COMMAND_REGISTER;
				OPERATOR_REGISTER0_DEFAULT <= ((IS_ADDRESS_POINTING_AT_US == 1'b1) && (MCU_OE == 1'b0) && (ACTUAL_OFFSET[8:0] == 9'd494)) ? MCU_BUS_import[15:0] : OPERATOR_REGISTER0_DEFAULT;
			end			
			
			// Instantiate			
			ASIC_Engine_Operator #(i) uEngine (
				.SysClock(clk_SPI_System), 
				.SPI_MOSI(engine_SPI_MOSI), 
				.SPI_MISO(engine_SPI_MISO), 
				.SPI_CLOCK(engine_SPI_CLOCK), 
				.SPI_NCS(engine_SPI_NCS), 
				.BusAddress(ACTUAL_OFFSET[8:0]), 
				.BusExport(Operators_Bus_Export), 
				.OE(MCU_OE), 
				.CE(IS_ADDRESS_POINTING_AT_US), 
				.BusImport(MCU_BUS_import), 
				.BusStrobe(Engine_Strobe),
				.OperatorBusy(Operator_Busy),
				.OPERATOR_COMMAND_REGISTER(OPERATOR_COMMAND_REGISTER),
				.OPERATOR_REGISTER0_DEFAULT(OPERATOR_REGISTER0_DEFAULT)
			);
			
			
					
			// Now, assign our controls
			assign asic_spi_cs[i]    = (Operator_Busy) ? engine_SPI_NCS   : (REG_SPI_switch[7:0] == i) ? MCU_SPI_NCS  : 1'b1;
			assign asic_spi_mosi[i]  = (Operator_Busy) ? engine_SPI_MOSI  : (REG_SPI_switch[7:0] == i) ? MCU_SPI_MOSI : 1'b0;
			assign asic_spi_clock[i] = (Operator_Busy) ? engine_SPI_CLOCK : MCU_SPI_CLK;
			assign engine_SPI_MISO   = asic_spi_miso[i];
			
			// Is this engine available? Tell the MCU
			assign SPI_Availability_Wire[i] = (Operator_Busy);

		end				
					
	endgenerate	
	
	// Now set our extended export values
	assign MCU_BUS_export = MCU_REQUESTING_BAR_MEMORY_READ ? BAR0_mem_read_data : Extended_Export;	
									
	assign Extended_Export = MCU_REQUESTING_TEMP_SENSOR_READ ? REG_temperature_sensor :
									 MCU_REQUESTING_SYSTEM_INFORMATION_READ ? REG_system_information :
									 MCU_REQUESTING_COMMAND_EXECUTION_READ ? REG_command_execution :
									 MCU_REQUESTING_COMMAND_STATUS_READ ? REG_command_status :
									 MCU_REQUESTING_ID_READ ? 32'hFF103A1E :
									 MCU_REQUESTING_LINK_STATUS_READ ? {31'b0, pcie_link_active} :
									 MCU_REQUESTING_FAN_READ ? {28'b0, FAN_CONTROL[3:0]} :
									 MCU_REQUESTING_SPI_AVAILABILITY_READ ? SPI_Availability_Wire :
									 MCU_REQUESTING_SPI_SWITCH_READ ? REG_SPI_switch :
									 MCU_REQUESTING_ASIC_PORB_READ ? {30'b0, asic_PORB2, asic_PORB1} : 
									 Operators_Bus_Export;
	
	
	assign MCU_SPI_MISO = (REG_SPI_switch[7:0] == 8'hFF) ? 1'b1 : asic_spi_miso[REG_SPI_switch[3:0]];
	
	
	// DEBUG
	assign LED_FPGA = led_pulse_counter[23] & led_pulse_counter[19];
	
endmodule
