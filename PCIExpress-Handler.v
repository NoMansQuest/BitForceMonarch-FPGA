`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    21:39:20 10/31/2013 
// Design Name: 
// Module Name:    PCIExpress-Handler 
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
`define CONVERT_ENDIAN(x) {x[7:0], x[15:8], x[23:16], x[31:24]}
	

module PCIExpress_Handler(

	  // PCI Express signals
	  pcie_intercepted_clock,
	  pcie_sync_clock,
	  pcie_link_active,
	  pcie_PERSTn,
	  pcie_hot_reset,
	  pcie_reset_completed,
	  pcie_tx_p,
	  pcie_tx_n,
	  pcie_rx_p,
	  pcie_rx_n,
	  	  
	  // BAR0 - Master Writes and Slave Reads
	  BAR0_mem_read_adrs,
	  BAR0_mem_read_clock,
	  BAR0_mem_read_data,
	  BAR0_mem_read_enable,
	  	  
	  // BAR1 - Master Reads and Slave Writes
	  BAR1_mem_write_adrs,
	  BAR1_mem_write_clock,
	  BAR1_mem_write_data,
	  BAR1_mem_write_enable,
	  
	  // BAR2 - Control Registers
	  BAR2_ADRS2_StatusRegister1,
	  BAR2_ADRS2_StatusRegister1_ReadStrobe,
	  BAR2_ADRS3_StatusRegister2,
	  BAR2_ADRS3_StatusRegister2_ReadStrobe,
	  BAR2_ADRS4_StatusRegister3,
	  BAR2_ADRS4_StatusRegister3_ReadStrobe,
	  BAR2_ADRS5_StatusRegister4,
	  BAR2_ADRS5_StatusRegister4_ReadStrobe,
	  
	  BAR2_ADRS0_Command1RegisterStrobe, // PCIE Wrote to our master command
	  BAR2_ADRS0_Command1RegisterData,   // PCIE master command write strobe
	  BAR2_ADRS1_Command2RegisterStrobe, 
	  BAR2_ADRS1_Command2RegisterData,

	  // Have we ever had any packets?
	  AnyTLPsReceivedEver,
	  
	  // Was memory request refused
	  MemoryRequestRefused,
	  MemoryRequestCompletedSuccessfully,
	  MemoryRequestInProgress,
	  
	  // Debug Condition Met
	  DebugConditionMet
	);

	output reg [2:0]MemoryRequestRefused;
	output reg MemoryRequestCompletedSuccessfully;
	output reg MemoryRequestInProgress;
	output reg DebugConditionMet = 1'b0;
	
	// Module ports
	output pcie_reset_completed;
	output pcie_sync_clock;
	output pcie_link_active;
	input  pcie_rx_p;
	input  pcie_rx_n;
	output pcie_tx_p;
	output pcie_tx_n;
	input  pcie_PERSTn;
	output pcie_hot_reset;
	
	// Debug Info
	output reg AnyTLPsReceivedEver = 1'b0;
		
   // BAR0 - Master Writes and Slave Reads
   input  [9:0]BAR0_mem_read_adrs;
   input  BAR0_mem_read_clock;
   output [31:0]BAR0_mem_read_data;
   input  BAR0_mem_read_enable;
	  
   // BAR1 - Master Reads and Slave Writes
   input [9:0]BAR1_mem_write_adrs;
   input BAR1_mem_write_clock;
   input [31:0]BAR1_mem_write_data;
   input BAR1_mem_write_enable;
  
   // BAR2 - Control Registers
	input [31:0]BAR2_ADRS2_StatusRegister1;	
	input [31:0]BAR2_ADRS3_StatusRegister2;		
   input [31:0]BAR2_ADRS4_StatusRegister3;
	input [31:0]BAR2_ADRS5_StatusRegister4;	
	output BAR2_ADRS2_StatusRegister1_ReadStrobe;
   output BAR2_ADRS3_StatusRegister2_ReadStrobe;
	output BAR2_ADRS4_StatusRegister3_ReadStrobe;
   output BAR2_ADRS5_StatusRegister4_ReadStrobe;
  
   output BAR2_ADRS0_Command1RegisterStrobe;
	output BAR2_ADRS1_Command2RegisterStrobe;
   output [31:0]BAR2_ADRS0_Command1RegisterData;   
   output [31:0]BAR2_ADRS1_Command2RegisterData;  

	 
	// Convert PCI Express clock to single-ended clock
	input pcie_intercepted_clock;

	// PCI Express sperical signals
	wire   pcie_link_up;
	wire   pcie_reset_request;
	assign pcie_link_active = pcie_link_up;
	assign pcie_hot_reset = pcie_reset_request;
	
	wire clk_sync_pcie; // This will be our clock for the PCI subsystem (left side of the RAM)
	assign pcie_sync_clock = clk_sync_pcie;
	
	wire pcie_tx_ready;
	wire [31:0]pcie_tx_data;
	reg  pcie_tx_last;
	reg  pcie_tx_valid;
	wire [5:0]pcie_tx_total_buffers_available;
	wire pcie_tx_buffer_available = (pcie_tx_total_buffers_available != 6'b0);


	wire [31:0]pcie_rx_data;
	reg  pcie_rx_ready;
	wire pcie_rx_valid;	
	wire [21:0]pcie_rx_user_info;
	reg  pcie_rx_nonposted_ok;
	wire pcie_rx_last_packet;
	
	wire pcie_cfg_turnoff_req;
	
	wire [07:0]pcie_cfg_bus_number;  
	wire [04:0]pcie_cfg_device_number;
	wire [02:0]pcie_cfg_function_number;
	
	reg pcie_cfg_err_ur;
	reg pcie_cfg_err_cor;                
 	reg pcie_cfg_err_posted;         
	reg pcie_cfg_err_cpl_abort;  	
	
	wire [47:0]pcie_cfg_err_tlp_cpl_header;
	wire pcie_cfg_err_cpl_rdy; // Set by core	
	
	assign pcie_link_active = pcie_link_up;
	
	wire pcie_received_hot_reset;
	
	// TLP Types
	parameter [6:0]TLP_MEMORY_READ_64Bit  = 7'b00_00000;
	parameter [6:0]TLP_MEMORY_WRITE_64Bit = 7'b11_00000;	
	
	parameter [6:0]TLP_MEMORY_READ_LOCKED = 7'b00_00001;
	parameter [6:0]TLP_MEMORY_READ_LOCKED_64Bit = 7'b01_00001;
	
	parameter [6:0]TLP_MEMORY_WRITE 		= 7'b10_00000;
	parameter [6:0]TLP_MEMORY_READ 		= 7'b00_00000;
	
	parameter [6:0]TLP_IO_READ 			= 7'b00_00010;
	parameter [6:0]TLP_IO_WRITE 			= 7'b10_00010;
	parameter [6:0]TLP_CONFIG_READ0 		= 7'b00_00100;
	parameter [6:0]TLP_CONFIG_WRITE0 	= 7'b10_00100;
	parameter [6:0]TLP_CONFIG_READ1 		= 7'b00_00101;
	parameter [6:0]TLP_CONFIG_WRITE1 	= 7'b10_00101;
	parameter [6:0]TLP_MSG 					= 7'b01_10000;
	parameter [6:0]TLP_MSG_DATA 			= 7'b11_10000;
	parameter [6:0]TLP_CPL 					= 7'b00_01010;
	parameter [6:0]TLP_CPL_DATA 			= 7'b10_01010;
	parameter [6:0]TLP_CPL_LOCKED 		= 7'b00_01011;
	parameter [6:0]TLP_CPL_DATA_LOCKED 	= 7'b10_01011;
	

   localparam PCI_EXP_EP_OUI    = 24'h000A35;
   localparam PCI_EXP_EP_DSN_1  = {{8'h1},PCI_EXP_EP_OUI};
   localparam PCI_EXP_EP_DSN_2  = 32'h00000001;
	
	assign pcie_reset_request = 1'b0;

	// Instantiate our PCI-Express CORE
	s6_pcie_v2_4 #(.FAST_TRAIN ("FALSE")) main_pci_express_port (
	
		  // PCI Express (PCI_EXP) Fabric Interface
		  .pci_exp_txp                        ( pcie_tx_p                 ),
		  .pci_exp_txn                        ( pcie_tx_n                 ),
		  .pci_exp_rxp                        ( pcie_rx_p                 ),
		  .pci_exp_rxn                        ( pcie_rx_n                 ),

		  // Transaction (TRN) Interface
		  // Common clock & reset
		  .user_lnk_up                        ( pcie_link_up              ),
		  .user_clk_out                       ( clk_sync_pcie             ),
		  .user_reset_out                     ( pcie_reset_completed      ),
		  
		  // Common flow control
		  .fc_sel                             ( 3'b000                      ),
		  .fc_nph                             ( ),
		  .fc_npd                             ( ),
		  .fc_ph                              ( ),
		  .fc_pd                              ( ),
		  .fc_cplh                            ( ),
		  .fc_cpld                            ( ),

		  // Transaction Tx
		  .s_axis_tx_tready                   ( pcie_tx_ready            ),
		  .s_axis_tx_tdata                    ( pcie_tx_data             ),
		  .s_axis_tx_tkeep                    ( 4'hF				           ), // Not for Spartan 6, drive to 0xF
		  .s_axis_tx_tuser                    ( 4'h0				           ), // Not for Spartan 6, drive low
		  .s_axis_tx_tlast                    ( pcie_tx_last             ),
		  .s_axis_tx_tvalid                   ( pcie_tx_valid            ),
		  .tx_err_drop                        ( 					           ),
		  .tx_buf_av                          ( pcie_tx_total_buffers_available),
		  .tx_cfg_req                         ( ),
		  .tx_cfg_gnt                         ( 1'b1			                 ), // Config packet priority maintained

		  // Transaction Rx
		  .m_axis_rx_tdata                    ( pcie_rx_data                ),
		  .m_axis_rx_tkeep                    ( ), 
		  .m_axis_rx_tlast                    ( pcie_rx_last_packet         ),
		  .m_axis_rx_tvalid                   ( pcie_rx_valid               ),
		  .m_axis_rx_tready                   ( pcie_rx_ready               ),
		  .m_axis_rx_tuser                    ( pcie_rx_user_info           ),
		  .rx_np_ok                           ( pcie_rx_nonposted_ok        ),

		  // Configuration (CFG) Interface
		  // Configuration space access
		  .cfg_do                             (     ),
		  .cfg_rd_wr_done                     (     ),
		  .cfg_dwaddr                         ( 0   ),
		  .cfg_rd_en                          ( 0   ), 
		  
		  // Error reporting
		  .cfg_err_ur                         ( pcie_cfg_err_ur     ),
		  .cfg_err_cor                        ( 1'b0				                   ),
		  .cfg_err_ecrc                       ( 1'b0					                ),
		  .cfg_err_cpl_timeout                ( 1'b0							          ),
		  .cfg_err_cpl_abort                  ( pcie_cfg_err_cpl_abort  ),
		  .cfg_err_posted                     ( pcie_cfg_err_posted     ),
		  .cfg_err_locked                     ( 1'b0              ),
		  .cfg_err_tlp_cpl_header             ( pcie_cfg_err_tlp_cpl_header      ),
		  .cfg_err_cpl_rdy                    ( pcie_cfg_err_cpl_rdy             ),
		  
		   // Interrupt generation
		  .cfg_interrupt                      ( 1'b0 ),
		  .cfg_interrupt_rdy                  ( ),
		  .cfg_interrupt_assert               ( 1'b0 ),
		  .cfg_interrupt_do                   ( ),
		  .cfg_interrupt_di                   ( 8'b0000000 ),
		  .cfg_interrupt_mmenable             ( ),
		  .cfg_interrupt_msienable            ( ),
		  
		  // Power management signaling
		  .cfg_turnoff_ok                     ( pcie_cfg_turnoff_req        ),
		  .cfg_to_turnoff                     ( pcie_cfg_turnoff_req        ),
		  .cfg_pm_wake                        ( 1'b1			                 ),
		  .cfg_pcie_link_state                ( 								     ),
		  .cfg_trn_pending                    ( 1'b0 ),
		  
		  // System configuration and status
		  .cfg_dsn                            ( {PCI_EXP_EP_DSN_2, PCI_EXP_EP_DSN_1} ), // XILINX by default
		  .cfg_bus_number                     ( pcie_cfg_bus_number              ),
		  .cfg_device_number                  ( pcie_cfg_device_number           ),
		  .cfg_function_number                ( pcie_cfg_function_number         ),
		  .cfg_status                         (                  ),
		  .cfg_command                        (                  ),
		  .cfg_dstatus                        (                  ),
		  .cfg_dcommand                       (                  ),
		  .cfg_lstatus                        (                  ),
		  .cfg_lcommand                       (                  ),

		  // System (SYS) Interface
		  .sys_clk                            ( pcie_intercepted_clock      ),
		  .sys_reset                          ( ~pcie_PERSTn             	  ),
		  .received_hot_reset                 ( pcie_received_hot_reset     )
  );		 

  // We instantiate two RAMs.
  // One for BAR0 (MOSI) and one for BAR1 (MISO)
  wire [3:0]BAR0_WRITE_ENABLE; // We have byte filtering
  wire [31:0]BAR0_WRITE_DATA;
  wire [9:0]BAR0_WRITE_ADDRESS;
  
  wire BAR1_READ_ENABLE;
  wire [31:0]BAR1_READ_DATA;
  wire [9:0]BAR1_READ_ADDRESS; 
 
  // Here the Computer Writes, MCU Reads
  blk_mem_gen_v6_3 BAR0_MEMORY_MOSI (
	  .clka(clk_sync_pcie), 
	  .ena(1'b1), 
	  .wea(BAR0_WRITE_ENABLE), 
	  .addra(BAR0_WRITE_ADDRESS), 
	  .dina(BAR0_WRITE_DATA), 
	  .clkb(BAR0_mem_read_clock), 
	  .enb(BAR0_mem_read_enable), 
	  .addrb(BAR0_mem_read_adrs), 
	  .doutb( {BAR0_mem_read_data[7:0],BAR0_mem_read_data[15:8], BAR0_mem_read_data[23:16], BAR0_mem_read_data[31:24]} ) 
  );
  
  // Here the MCU writes, the computer reads
  blk_mem_gen_v6_3 BAR1_MEMORY_MISO (
	  .clka(BAR1_mem_write_clock), 
	  .ena(BAR1_mem_write_enable), 
	  .wea(4'hF),  // All bytes enabled for MCU side
	  .addra(BAR1_mem_write_adrs), 
	  .dina( {BAR1_mem_write_data[7:0], BAR1_mem_write_data[15:8], BAR1_mem_write_data[23:16], BAR1_mem_write_data[31:24]} ), 
	  .clkb(clk_sync_pcie), 
	  .enb(1'b1), 
	  .addrb(BAR1_READ_ADDRESS), 
	  .doutb(BAR1_READ_DATA) 
  );
  
  
  ////////////////////////////////////////////////
  // PCI Express State Machines
  ////////////////////////////////////////////////
  
    

  //////////////////////////////////////////
  // Incoming TLP preliminary data
  reg  [31:0]pcie_tlp_DW0;
  reg  [31:0]pcie_tlp_DW1;
  reg  [31:0]pcie_tlp_DW2;    
  wire [31:0]pcie_incoming_first_DW;
  wire [15:0]pcie_incoming_requester_ID;
  wire [7:0]pcie_incoming_TAG;
  wire [3:0]pcie_incoming_last_DW_BE;
  wire [3:0]pcie_incoming_first_DW_BE;
  reg  [9:0]pcie_incoming_length;
  wire [1:0]pcie_incoming_ATTR;
  wire [1:0]pcie_incoming_FMT;
  wire [4:0]pcie_incoming_TYPE;
  wire [2:0]pcie_incoming_TC;
  wire [3:0]pcie_incoming_LAST_BE;
  wire [3:0]pcie_incoming_FIRST_BE;
  wire [9:0]pcie_incoming_length_wire;
  reg  [9:0]pcie_incoming_address; // Both BAR1 and BAR0 are 1024DW (4096Bytes). BAR2 is even smaller
  reg  [9:0]pcie_outgoing_address; // Both BAR1 and BAR0 are 1024DW (4096Bytes). BAR2 is even smaller
  wire [9:0]pcie_incoming_address_original = pcie_tlp_DW2[11:2];

  // Information
  assign pcie_incoming_length_wire = pcie_tlp_DW0[9:0];
  assign pcie_incoming_TAG  = pcie_tlp_DW1[15:8];
  assign pcie_incoming_ATTR = pcie_tlp_DW0[13:12];
  assign pcie_incoming_TC   = pcie_tlp_DW0[22:20];
  assign pcie_incoming_requester_ID	 = pcie_tlp_DW1[31:16];
  assign pcie_incoming_FMT				 = pcie_tlp_DW0[30:29];
  assign pcie_incoming_TYPE			 = pcie_tlp_DW0[28:24];
  assign pcie_incoming_LAST_BE		 = pcie_tlp_DW1[7:4];
  assign pcie_incoming_FIRST_BE		 = pcie_tlp_DW1[3:0];  
  
  wire  pcie_incoming_TLP_is_3DW_NoData   = ((pcie_incoming_FMT == 2'b00) ? 1'b1 : 1'b0);
  wire  pcie_incoming_TLP_is_4DW_NoData   = ((pcie_incoming_FMT == 2'b01) ? 1'b1 : 1'b0);
  wire  pcie_incoming_TLP_is_3DW_WithData = ((pcie_incoming_FMT == 2'b10) ? 1'b1 : 1'b0);
  wire  pcie_incoming_TLP_is_4DW_WithData = ((pcie_incoming_FMT == 2'b11) ? 1'b1 : 1'b0);
  
  wire  [6:0]TLP_FMT_TYPE   = {pcie_incoming_FMT, pcie_incoming_TYPE};
  wire  IS_TLP_SUPPORTED    = ((TLP_FMT_TYPE == TLP_MEMORY_READ) || (TLP_FMT_TYPE == TLP_MEMORY_WRITE)) ? 1'b1 : 1'b0;
  wire  IS_TLP_64BIT_READ   = (pcie_incoming_TLP_is_4DW_NoData | pcie_incoming_TLP_is_4DW_WithData) & ((pcie_incoming_TYPE == 5'b000000) ? 1'b1 : 1'b0);
  
  wire pcie_incoming_trans_is_write = (TLP_FMT_TYPE == TLP_MEMORY_WRITE) ? 1'b1 : 1'b0 ;
  wire pcie_incoming_trans_is_read  = (TLP_FMT_TYPE == TLP_MEMORY_READ)  ? 1'b1 : 1'b0 ;

  
  // Set correct PCI-E TLP Error Header
  assign pcie_cfg_err_tlp_cpl_header = 
					{pcie_tlp_DW2[8:2],         // Lower Address
					 pcie_tlp_DW0[9:0], 2'b00,  // Byte Count
					 pcie_tlp_DW0[22:20], 		 // TC
					 pcie_tlp_DW0[13:12],		 // ATTR
					 pcie_tlp_DW1[31:16], 		 // Requester ID
					 pcie_tlp_DW1[15:8]		    // TAG
					 };  

  /////////////////////////////////////////
  reg  [8:0]pcie_rx_user_info_locked;
  
  wire pcie_rx_bad_transact = pcie_rx_user_info[1]; // Not taken from memory, since it's in RX stage
  
  /* The rest we read from memorized value */
  wire pcie_rx_BAR0_hit     = pcie_rx_user_info_locked[2];
  wire pcie_rx_BAR1_hit     = pcie_rx_user_info_locked[3];
  wire pcie_rx_BAR2_hit     = pcie_rx_user_info_locked[4];
  wire pcie_rx_BAR3_hit     = pcie_rx_user_info_locked[5];
  wire pcie_rx_BAR4_hit     = pcie_rx_user_info_locked[6];
  wire pcie_rx_BAR5_hit     = pcie_rx_user_info_locked[7];
  wire pcie_rx_BAR6_hit     = pcie_rx_user_info_locked[8];	
  
  reg  pcie_rx_first_stage_data; // This is set when the FIRST DWORD is going to be received from PCI Express
  reg  pcie_commit_data; // When set, we must accept the pci-express data and write it somewhere
  wire pcie_commit_to_BRAM = (pcie_commit_data) & (pcie_rx_BAR0_hit);
									  // When set, we must either write data to registers or to BRAMs
												
  wire pcie_commit_to_registers_BAR = (pcie_commit_data) & (pcie_rx_BAR2_hit);
  wire pcie_commit_to_command0 = pcie_commit_to_registers_BAR & ((pcie_incoming_address[4:0] == 5'h0) ? 1'b1 : 1'b0);
  wire pcie_commit_to_command1 = pcie_commit_to_registers_BAR & ((pcie_incoming_address[4:0] == 5'h1) ? 1'b1 : 1'b0);
  
  assign BAR2_ADRS0_Command1RegisterStrobe = pcie_commit_to_command0;
  assign BAR2_ADRS1_Command2RegisterStrobe = pcie_commit_to_command1;
  assign BAR2_ADRS0_Command1RegisterData = `CONVERT_ENDIAN(pcie_rx_data); 
  assign BAR2_ADRS1_Command2RegisterData = `CONVERT_ENDIAN(pcie_rx_data);  
  
  // BAR0 Write Control
  wire [3:0]BAR0_WRITE_FILTER = (pcie_rx_first_stage_data == 1) ? pcie_incoming_FIRST_BE :
										  (pcie_rx_last_packet == 1) ? pcie_incoming_LAST_BE : 4'b1111 ;
  assign BAR0_WRITE_ENABLE  = (pcie_commit_to_BRAM == 0) ? 4'b0 : BAR0_WRITE_FILTER;
  assign BAR0_WRITE_ADDRESS = pcie_incoming_address;
  assign BAR0_WRITE_DATA    = pcie_rx_data;
  
  // BAR1 Read Address (it's active by default)
  assign BAR1_READ_ADDRESS  = pcie_outgoing_address;
  

  // Different states
  parameter PCIE_INCOMING_STATE_IDLE   = 4'h0; // We capture the first DW of TLP
  parameter PCIE_INCOMING_STATE_STAGE1 = 4'h1; // We capture the second DW of TLP
  parameter PCIE_INCOMING_STATE_STAGE2 = 4'h2; // We capture the third DW of TLP
  parameter PCIE_INCOMING_STATE_STAGE3 = 4'h3; // Here we are either receiving data on an incoming RX TLP, or we're preparing for a response 
  parameter PCIE_INCOMING_STATE_STAGE4 = 4'h4; 
  parameter PCIE_INCOMING_STATE_STAGE5 = 4'h5; 
  
  reg  [3:0]pcie_transaction_state; // State of the actual state machine

  // General abort, which can have different sources
  reg  pcie_tlp_completion_initiate;   // Activates the completion generator state machine
  reg  pcie_tlp_completion_done; // Set by the completion-generator, it indicates that completion was generated and sent
  
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  // Incoming TLP State Machine
  //////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
  always @(posedge pcie_sync_clock)
  begin
		// Default reset state
		if ((!pcie_PERSTn) || pcie_reset_request) 
		begin
			pcie_transaction_state <= PCIE_INCOMING_STATE_IDLE;
			pcie_rx_ready <= 1'b1;
			pcie_rx_nonposted_ok <= 1'b1;
			pcie_incoming_length <= 10'b0;
			pcie_commit_data <= 1'b0;
			pcie_rx_first_stage_data <= 1'b0;
			
			// Clear all errors
			pcie_cfg_err_ur  	  <= 1'b0;             
			pcie_cfg_err_cor 	  <= 1'b0;                
 			pcie_cfg_err_posted <= 1'b0;
			
			
			// Reset TLP Completion Request
			pcie_tlp_completion_initiate <= 1'b0;
			
			// Reset debugging
			AnyTLPsReceivedEver <= 1'b0;			
		end
		else
		begin			
			// STAGE IDLE: Waiting for a TLP
			if (pcie_transaction_state == PCIE_INCOMING_STATE_IDLE)
			begin
				// Initialize some values
				pcie_rx_ready <= 1'b1;
				pcie_rx_nonposted_ok <= 1'b1;
				pcie_incoming_length <= 10'b0;
				pcie_rx_first_stage_data <= 1'b0;
				pcie_commit_data <= 1'b0; // Do not write the actual data anywhere...
				pcie_tlp_completion_initiate <= 1'b0;
				
						
				// Proceed
				if (pcie_rx_valid && (!pcie_rx_bad_transact)) // Poisoned TLPs wont start the state machine
				begin
					// Data on RX is valid. Capture it and go to next state
					pcie_tlp_DW0 <= pcie_rx_data;
					pcie_incoming_length <= pcie_rx_data[9:0];
					pcie_transaction_state <= PCIE_INCOMING_STATE_STAGE1;
			
					// Memorize user info, we'll use it later
					pcie_rx_user_info_locked <= pcie_rx_user_info[8:0];
						
					// Set debug info
					AnyTLPsReceivedEver <= 1'b1;
				end			
				else
				begin
					pcie_transaction_state <= PCIE_INCOMING_STATE_IDLE;	
					pcie_incoming_length <= 10'b0;				
				end			
			end
			else if (pcie_transaction_state == PCIE_INCOMING_STATE_STAGE1) // Capture second DW of TLP
			begin
				if (~pcie_rx_valid)
				begin
					pcie_transaction_state <= PCIE_INCOMING_STATE_STAGE1;				
				end
				else
				begin
					// Data on RX is valid. Capture it and go to next state
					pcie_tlp_DW1 <= pcie_rx_data;
					pcie_transaction_state <= (pcie_rx_last_packet) ? PCIE_INCOMING_STATE_IDLE :
													(pcie_rx_valid) ? PCIE_INCOMING_STATE_STAGE2 : PCIE_INCOMING_STATE_STAGE1 ;				
				end
			end
			else if (pcie_transaction_state == PCIE_INCOMING_STATE_STAGE2) // Capture third DW of TLP
			begin
				// Proceed
				if (~pcie_rx_valid) // tvalid is gone?
				begin
					pcie_transaction_state <= PCIE_INCOMING_STATE_IDLE;
				end
				else
				begin
					// Data on RX is valid. Capture it and go to next state
					pcie_incoming_address <= pcie_rx_data[11:2];
					
					// Save the DW2 as well
					pcie_tlp_DW2 <= pcie_rx_data;
					
					// Ok next stage depends on whether this is a READ TLP or a WRITE TLP.
					// For WRITE TLP we simply go to stage 4 until 'tlast' is set and we're done..
					// We also increment the address 
					if (pcie_incoming_trans_is_write)
					begin
						// Ok, do we see tlast ? if so, we have a problem
						if (pcie_rx_last_packet)
						begin
						
							// Handle the error
							// [ NOTHING FOR THE MOMENT, WE'LL SEE IT LATER ]
							pcie_cfg_err_ur <= 1'b1; // Correctable error, causing no harm
							pcie_cfg_err_posted <= 1'b1; // This of course was a posted error
							
							// And return to IDLE state
							pcie_transaction_state <= PCIE_INCOMING_STATE_IDLE;
						end
						else
						begin
							// Was length Zero? If so, we go to IDLE state and wont complain
							// If not, we'll move to Stage 3 - Which is intercepting data
							pcie_rx_first_stage_data <= 1'b1; // Next cycle will be our first received data. This must be set to 1st BE is applied;
							pcie_commit_data <= (IS_TLP_SUPPORTED) ? 1'b1 : 1'b0; // Next stage will contain data, so we must enable commit at this stage, unless the TLP is NOT supported
							pcie_transaction_state <= PCIE_INCOMING_STATE_STAGE3;							
						end
			
					end
					else	 // Read request
					begin
						// At this stage, if pcie_rx_last_packet is NOT set, then we have a problem.
						// Otherwise, we have to active TLP Generator to generate and send a completion
						if (!pcie_rx_last_packet)
						begin
							
							// We have an error
							pcie_cfg_err_posted <= 1'b1; // This is a posted error
							pcie_cfg_err_ur <= 1'b1; // User error request
							
							// Go back to IDLE
							pcie_transaction_state <= PCIE_INCOMING_STATE_IDLE;						
						end
						else
						begin
							// We request TLP Completion
							pcie_tlp_completion_initiate <= 1'b1;	

							// We DO NOT have any errors
							pcie_cfg_err_posted <= 1'b0; // This is a posted error
							pcie_cfg_err_ur <= 1'b0; // User error request							
							
							// Now we no longer allow the Core to send us packets, by deasserting 
							pcie_rx_ready <= 1'b0;
							pcie_transaction_state <= PCIE_INCOMING_STATE_STAGE4;									
							DebugConditionMet <= IS_TLP_64BIT_READ;
	 					end			
					end						
				end
			end
			else if (pcie_transaction_state == PCIE_INCOMING_STATE_STAGE3) // Wait for Memory Write to finish. Then we return to IDLE
			begin
				// We are no longer in the first stage of write
				pcie_rx_first_stage_data <= 1'b0; 
						
				// Is it last packet? 
				if (pcie_rx_last_packet)
				begin
					// Stop receiving data at this stage (Which applies to next cycle)
					pcie_commit_data <= 1'b0; 
					
					// Go back to IDLE
					pcie_transaction_state <= PCIE_INCOMING_STATE_IDLE;					
				end
				else
				begin
					// Stop receiving data at this stage (Which applies to next cycle)
					pcie_commit_data <= (IS_TLP_SUPPORTED) ? 1'b1 : 1'b0; 
					
					// We no longer accept data, we're waiting for completion to finish
					pcie_rx_ready <= 1'b0;
					
					// Go back to IDLE
					pcie_transaction_state <= PCIE_INCOMING_STATE_STAGE3;						
				end
			end
			else if (pcie_transaction_state == PCIE_INCOMING_STATE_STAGE4) // Wait for completion
			begin
				// We maintain rx_read de-asserted, until the completion is sent
				pcie_rx_ready <= 1'b0;
				pcie_tlp_completion_initiate <= 1'b0;		

				// Wait until pcie_tlp_completion_done is asserted
				pcie_transaction_state <= (pcie_tlp_completion_done) ? PCIE_INCOMING_STATE_IDLE : PCIE_INCOMING_STATE_STAGE4;
			end		
			else
			begin								
				// Go back to IDLE ( ILLEGAL STATE )
				pcie_transaction_state <= PCIE_INCOMING_STATE_IDLE;		
			end
		end  
  end
  
  
   // Now here, we need to generate completion TLP
	wire pcie_tx_select_BAR1_memory = pcie_rx_BAR1_hit;
	wire pcie_tx_select_StatusRegister1 = (pcie_rx_BAR2_hit) & ((pcie_outgoing_address[4:0] == 5'h2) ? 1'b1 : 1'b0);
	wire pcie_tx_select_StatusRegister2 = (pcie_rx_BAR2_hit) & ((pcie_outgoing_address[4:0] == 5'h3) ? 1'b1 : 1'b0);
	wire pcie_tx_select_StatusRegister3 = (pcie_rx_BAR2_hit) & ((pcie_outgoing_address[4:0] == 5'h4) ? 1'b1 : 1'b0);
	wire pcie_tx_select_StatusRegister4 = (pcie_rx_BAR2_hit) & ((pcie_outgoing_address[4:0] == 5'h5) ? 1'b1 : 1'b0);
	wire pcie_tx_select_ID = (pcie_rx_BAR2_hit) & ((pcie_outgoing_address[4:0] == 5'h6) ? 1'b1 : 1'b0);
	
	assign BAR2_ADRS2_StatusRegister1_ReadStrobe = (pcie_tx_select_StatusRegister1) & pcie_tx_valid & pcie_tx_ready;
   assign BAR2_ADRS3_StatusRegister2_ReadStrobe = (pcie_tx_select_StatusRegister2) & pcie_tx_valid & pcie_tx_ready;
	assign BAR2_ADRS4_StatusRegister3_ReadStrobe = (pcie_tx_select_StatusRegister3) & pcie_tx_valid & pcie_tx_ready;
   assign BAR2_ADRS5_StatusRegister4_ReadStrobe = (pcie_tx_select_StatusRegister4) & pcie_tx_valid & pcie_tx_ready;
	
	parameter pcie_Cpl_IDLE   = 4'h0;
	parameter pcie_Cpl_STAGE0 = 4'hF;
	parameter pcie_Cpl_STAGE1 = 4'h1;
	parameter pcie_Cpl_STAGE2 = 4'h2;
	parameter pcie_Cpl_STAGE3 = 4'h3;
	parameter pcie_Cpl_STAGE4 = 4'h4;
	parameter pcie_Cpl_STAGE5 = 4'h5;
	parameter pcie_Cpl_STAGE6 = 4'h6;
	
	reg [3:0]pcie_completion_module_state;

	parameter MAX_TLP_PAYLOAD = 256;
	reg  [9:0]pcie_completion_data_length; // Actual completion length
	reg  [9:0]pcie_completion_data_total_sent;
	wire [9:0]pcie_completion_data_total_remaining = pcie_completion_data_length - pcie_completion_data_total_sent;
	wire [8:0]pcie_actual_tlp_data_length = ((pcie_completion_data_total_remaining) > MAX_TLP_PAYLOAD) ? MAX_TLP_PAYLOAD : pcie_completion_data_total_remaining;
	reg  [9:0]pcie_actual_tlp_total_to_send;  // This captures the 'pcie_actual_tlp_data_length' and decrements until we reach zero
	wire [9:0]pcie_outgoing_address_start_point = pcie_completion_data_total_sent + pcie_incoming_address_original;
	wire pcie_is_first_TLP = (pcie_completion_data_total_sent == 0) ? 1'b1 : 1'b0;
	wire [15:0]pcie_Completer_ID = {pcie_cfg_bus_number, pcie_cfg_device_number, pcie_cfg_function_number};	
	localparam TLP_TYPE_CplD = 5'b01010;
	
	
	reg [11:0] _be_first_subtract;
	reg [11:0] _be_last_subtract;
	
   always @* begin
		 casex (pcie_incoming_FIRST_BE[3:0])
			4'b1xx1 : _be_first_subtract = 12'h000;
			4'b01x1 : _be_first_subtract = 12'h001;
			4'b1x10 : _be_first_subtract = 12'h001;
			4'b0011 : _be_first_subtract = 12'h002;
			4'b0110 : _be_first_subtract = 12'h002;
			4'b1100 : _be_first_subtract = 12'h002;
			4'b0001 : _be_first_subtract = 12'h003;
			4'b0010 : _be_first_subtract = 12'h003;
			4'b0100 : _be_first_subtract = 12'h003;
			4'b1000 : _be_first_subtract = 12'h003;
			4'b0000 : _be_first_subtract = 12'h004;
		 endcase
   end
	
	always @* begin
		 casex (pcie_incoming_LAST_BE[3:0])
			4'b1xx1 : _be_last_subtract = 12'h000;
			4'b01x1 : _be_last_subtract = 12'h001;
			4'b1x10 : _be_last_subtract = 12'h001;
			4'b0011 : _be_last_subtract = 12'h002;
			4'b0110 : _be_last_subtract = 12'h002;
			4'b1100 : _be_last_subtract = 12'h002;
			4'b0001 : _be_last_subtract = 12'h003;
			4'b0010 : _be_last_subtract = 12'h003;
			4'b0100 : _be_last_subtract = 12'h003;
			4'b1000 : _be_last_subtract = 12'h003;
			4'b0000 : _be_last_subtract = 12'h004;
		 endcase
   end

	wire pcie_is_first_completion_stage = (pcie_completion_data_total_sent == 0) ? 1'b1 : 1'b0;
	wire pcie_is_last_completion_stage  = (pcie_completion_data_total_remaining <= MAX_TLP_PAYLOAD) ? 1'b1 : 1'b0;
	wire [11:0]__be_to_subtract = (pcie_is_first_completion_stage) ? _be_first_subtract :
										   (pcie_is_last_completion_stage) ?  _be_last_subtract  : 12'b0;
	wire [11:0]pcie_actual_tlp_byte_count = {1'b0, pcie_actual_tlp_data_length, 2'b00} - __be_to_subtract;
	
	
	// Byte Address
	reg  [6:0]__lower_addr_first_stage;
	wire [6:0]__lower_addr_other_stages = {pcie_outgoing_address_start_point[4:0], 2'b00};
	
   always @* begin
    casex ({pcie_incoming_FIRST_BE[3:0]})
      4'b0000 : __lower_addr_first_stage = {pcie_outgoing_address_start_point[4:0], 2'b00};
      4'bxxx1 : __lower_addr_first_stage = {pcie_outgoing_address_start_point[4:0], 2'b00};
      4'bxx10 : __lower_addr_first_stage = {pcie_outgoing_address_start_point[4:0], 2'b01};
      4'bx100 : __lower_addr_first_stage = {pcie_outgoing_address_start_point[4:0], 2'b10};
      4'b1000 : __lower_addr_first_stage = {pcie_outgoing_address_start_point[4:0], 2'b11};
    endcase
   end	
	
	/////////////////////////// R  ,  FMT , TYPE         ,  R  ,  Traffic Value,   RRRR,  TD ,  EP , ------- ATTR -----,  RR  ,  Length of the completion	
	wire [31:0]pcie_Cpl_DW0 = {1'b0, 2'b10, TLP_TYPE_CplD, 1'b0, pcie_incoming_TC, 4'b0, 1'b0, 1'b0, pcie_incoming_ATTR, 2'b0, {1'b0, pcie_actual_tlp_data_length} }	;
	wire [31:0]pcie_Cpl_DW1 = {pcie_Completer_ID, 3'b000, 1'b0, pcie_actual_tlp_byte_count}; 
	wire [31:0]pcie_Cpl_DW2 = {pcie_incoming_requester_ID, pcie_incoming_TAG, 1'b0, (pcie_is_first_TLP) ? __lower_addr_first_stage : __lower_addr_other_stages};
	
	
	// In this case, we'll just zero a "0x00000000" data
	wire pcie_ZERO_LENGTH_MEMORY_READ_REQUEST = ((pcie_incoming_length_wire == 9'b01) && (pcie_incoming_FIRST_BE == 4'b0)) ? 1'b1 : 1'b0;
	
	
	// Proceed
	assign pcie_tx_data = (pcie_completion_module_state == pcie_Cpl_STAGE1) ? pcie_Cpl_DW0 :
								 (pcie_completion_module_state == pcie_Cpl_STAGE2) ? pcie_Cpl_DW1 :
								 (pcie_completion_module_state == pcie_Cpl_STAGE3) ? pcie_Cpl_DW2 :
								 (pcie_tx_select_ID) ? 32'h1E3A10FF :   // 32'hFF103A1E in BigEndian mode
								 (pcie_tx_select_BAR1_memory) 	 ? BAR1_READ_DATA : // This one has already been converted before, so no endian conversion is needed
								 (pcie_tx_select_StatusRegister1) ? `CONVERT_ENDIAN(BAR2_ADRS2_StatusRegister1) :
								 (pcie_tx_select_StatusRegister2) ? `CONVERT_ENDIAN(BAR2_ADRS3_StatusRegister2) :
								 (pcie_tx_select_StatusRegister3) ? `CONVERT_ENDIAN(BAR2_ADRS4_StatusRegister3) :
								 (pcie_tx_select_StatusRegister4) ? `CONVERT_ENDIAN(BAR2_ADRS5_StatusRegister4) :
								 {pcie_rx_BAR2_hit, pcie_rx_BAR1_hit, pcie_rx_BAR0_hit, 19'b0, pcie_outgoing_address};
								 //32'hAAAABBBB;	
	
	
	// When to set DebugConditionMet
	wire __single_byte_operation = ((pcie_incoming_FIRST_BE  == 4'b1000) || 
											  (pcie_incoming_FIRST_BE  == 4'b0100) ||
											  (pcie_incoming_FIRST_BE  == 4'b0010) ||
											  (pcie_incoming_FIRST_BE  == 4'b0001)) ? 1'b1 : 1'b0;
		
	wire pcie_memory_request_is_overlapping_BAR1 = ((pcie_rx_BAR1_hit) && ((pcie_incoming_length_wire + pcie_incoming_address_original) > 1024)) ? 1'b1 : 1'b0;
	wire pcie_memory_request_is_overlapping_BAR2 = ((pcie_rx_BAR2_hit) && ((pcie_incoming_length_wire + pcie_incoming_address_original[4:0]) > 128)) ? 1'b1 : 1'b0;
	wire pcie_memory_request_is_reading_BAR0     =   pcie_rx_BAR0_hit;
	wire pcie_memory_request_is_unknown_BAR      = ~(pcie_rx_BAR1_hit | pcie_rx_BAR2_hit | pcie_rx_BAR0_hit);
	
	wire pcie_memory_request_refuse = (pcie_memory_request_is_overlapping_BAR1 | pcie_memory_request_is_overlapping_BAR2 |
												  pcie_memory_request_is_reading_BAR0 		| pcie_memory_request_is_unknown_BAR 		| 
												  ~IS_TLP_SUPPORTED);
	
	wire [2:0]pcie_assigned_value_to_memory_refused = (pcie_memory_request_is_unknown_BAR) ? 3'b001 : 3'b111;
															  
							
	wire __reset_condition = (~pcie_PERSTn);
	wire pcie_completion_state_machine_in_progress = ((pcie_completion_module_state != pcie_Cpl_IDLE) && (__reset_condition == 1'b0)) ? 1'b1 : 1'b0;
	
   always @(posedge pcie_sync_clock)
   begin
        // Default reset state
        if (__reset_condition)
        begin
            pcie_outgoing_address <= 10'b0; // We reset the outgoing address
            pcie_tlp_completion_done <= 1'b0;
            pcie_completion_module_state <= pcie_Cpl_IDLE;
            pcie_completion_data_total_sent <= 10'b0;
            pcie_completion_data_length <= 10'b0;
            pcie_tx_last <= 1'b0;
        end
        else
        begin
            // State Machine is here...
            if (pcie_completion_module_state == pcie_Cpl_IDLE)
            begin
                // Clear Error Flags
                pcie_cfg_err_cpl_abort   <= 1'b0;

                // We are not done here...
                pcie_tlp_completion_done <= 1'b0;
                pcie_completion_data_total_sent <= 10'b0;
                pcie_completion_data_length <= pcie_incoming_length_wire;
                pcie_actual_tlp_total_to_send <= 0;
                pcie_outgoing_address <= pcie_outgoing_address_start_point;
                pcie_tx_valid <= 1'b0;
                pcie_tx_last <= 1'b0;

                // Machine starts when pcie_tlp_completion_initiate is asserted
                pcie_completion_module_state <= (pcie_tlp_completion_initiate == 1'b1) ? pcie_Cpl_STAGE0 : pcie_Cpl_IDLE;
            end

            else if (pcie_completion_module_state == pcie_Cpl_STAGE0) // Here we check if the request is supported. If not, cfg_err_ur...
            begin

                // Generally we're not done here...
                pcie_tlp_completion_done <= 1'b0;
                pcie_tx_valid <= 1'b0; // Our data is NOT valid

                // Set Address
                pcie_outgoing_address <= pcie_outgoing_address_start_point;

				 // Proceed to next stage (If a TLP Buffer is available)
                pcie_completion_module_state <= (pcie_tx_total_buffers_available == 6'b0) ? pcie_Cpl_STAGE0 : pcie_Cpl_STAGE1;
                pcie_tx_valid <= (pcie_tx_total_buffers_available == 6'b0) ? 1'b0 : 1'b1;
            end

            else if ((pcie_completion_module_state == pcie_Cpl_STAGE1)||
                        (pcie_completion_module_state == pcie_Cpl_STAGE2)||
                        (pcie_completion_module_state == pcie_Cpl_STAGE3))  //////////// SEND Cpl_DW0, Cpl_DW1, Cpl_DW2
            begin

                // We are not done here...
                pcie_tlp_completion_done <= 1'b0;
                pcie_tx_valid <= 1'b1; // Our data is valid in these stages

                // Set Address
                pcie_outgoing_address <= pcie_outgoing_address_start_point;

                // At this stage, we initialize all registers and prepare to transfer the first DWORD of TLP
                // (Minus one, because by the time we reach the next stage, system has already outputed a DWORD)
                // (NOTE: CAPTURE THIS AT FIRST STAGE ONLY)
                pcie_actual_tlp_total_to_send <= (pcie_completion_module_state == pcie_Cpl_STAGE1) ? (pcie_actual_tlp_data_length) : pcie_actual_tlp_total_to_send;

                // Wait for TX RDY
                if ((pcie_tx_ready == 1'b0) || (pcie_tx_total_buffers_available == 6'b0))
                begin
                    // We must wait, as we cannot send any data (Either no buffer is available or core is not ready)
                    pcie_completion_module_state <= pcie_completion_module_state;
                end
                else
                begin
                    pcie_completion_module_state <= pcie_completion_module_state + 4'b0001; // Go to next stage (up until pcie_Cpl_STAGE3)

                    // We already have sent a DWORD (if we're at stage 3)
                    pcie_tx_last <= (pcie_completion_module_state == pcie_Cpl_STAGE3) ? ((pcie_actual_tlp_total_to_send == 10'b1) ? 1'b1 : 1'b0) : 1'b0;
                    pcie_completion_data_total_sent <= (pcie_completion_module_state == pcie_Cpl_STAGE3) ? (pcie_completion_data_total_sent + 10'b01) : pcie_completion_data_total_sent;
                end
            end

            else if (pcie_completion_module_state == pcie_Cpl_STAGE4)  //////////// DATA TRANSFER STAGE
            begin

                // We are not done here...
                pcie_tlp_completion_done <= 1'b0;

                // Wait for TX RDY
                if ((pcie_tx_ready == 1'b1))
                begin
                    // Address Increment and Total-Sent decerement, the usual stuff...
                    pcie_outgoing_address <= pcie_outgoing_address + 10'b01;
                    pcie_actual_tlp_total_to_send <= pcie_actual_tlp_total_to_send - 10'b01;
                    pcie_tx_valid <= ((pcie_tx_last == 1'b1) || (pcie_actual_tlp_total_to_send == 10'b00)) ? 1'b0 : 1'b1; // Our data is valid in these stages
                    pcie_tx_last <= (pcie_actual_tlp_total_to_send == 10'h02) ? 1'b1 : 1'b0;

                    // Is this the last DWORD we're sending?
                    if (pcie_tx_last) // Final stage reached. Decide what you want to do regarding the next stage
                    begin
                        // Has the transaction finished?
                        pcie_completion_module_state <= ((pcie_completion_data_total_sent) == pcie_completion_data_length) ? pcie_Cpl_STAGE5 : pcie_Cpl_STAGE0;
                    end
                    else
                    begin
                        // We just return to this stage as usual, and increment total sent (as long as tx_last is not asserted)
								pcie_completion_data_total_sent <= pcie_completion_data_total_sent + 10'b01;
                        pcie_completion_module_state <= pcie_Cpl_STAGE4;
                    end
                end
                else
                begin
                    pcie_tx_valid <= pcie_tx_valid;
                    pcie_completion_module_state <= pcie_completion_module_state;   // Go to next stage (up until pcie_Cpl_STAGE3)
                end
            end

            /* FINAL STAGE */
            else if (pcie_completion_module_state == pcie_Cpl_STAGE5)  //////////////// Terminating this whole Memory-Read request TLP
            begin

                if ((pcie_tx_ready == 1'b1))
                begin
                    // We are done here... Finished...
                    pcie_tlp_completion_done <= 1'b1;
                    pcie_tx_valid <= 1'b0; // Once we reach here, we need to de-assert the tx_valid. Since the data we present is not longer valid

                    pcie_actual_tlp_total_to_send <= 10'b0;
                    pcie_completion_module_state  <= pcie_Cpl_IDLE; // We are done, return to IDLE
                end
                else
                begin
                    // We shouldn't do anything and repeat this cycle. The last stage was not taken by core, since it's RDY was disabled the stage before
                    pcie_completion_module_state <= pcie_Cpl_STAGE5;
                end
            end
            else
            begin
                // We are not done here...
                pcie_tlp_completion_done <= 1'b1;
                pcie_completion_module_state <= pcie_Cpl_IDLE;
            end
        end
    end
endmodule
